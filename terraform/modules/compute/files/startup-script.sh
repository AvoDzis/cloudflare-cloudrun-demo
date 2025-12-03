#!/bin/bash
set -e

# Log all output
exec > >(tee -a /var/log/startup-script.log)
exec 2>&1

echo "Starting VM initialization..."

# Update system
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    echo "Docker installed successfully"
else
    echo "Docker already installed"
fi

# Create directory for PostgreSQL data
mkdir -p /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

# Run PostgreSQL container
echo "Starting PostgreSQL container..."
docker run -d \
    --name postgres \
    --restart unless-stopped \
    -e POSTGRES_DB=${DB_NAME} \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${DB_PASSWORD} \
    -p 5432:5432 \
    -v /var/lib/postgresql/data:/var/lib/postgresql/data \
    postgres:15-alpine \
    -c listen_addresses='*' \
    -c max_connections=100

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker exec postgres pg_isready -U ${DB_USER} -d ${DB_NAME}; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 2
done

echo "PostgreSQL is ready!"

# Initialize database schema
echo "Initializing database schema..."
docker exec -i postgres psql -U ${DB_USER} -d ${DB_NAME} <<'EOSQL'
CREATE TABLE IF NOT EXISTS quotes (
    id SERIAL PRIMARY KEY,
    quote TEXT NOT NULL,
    author VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample quotes if table is empty
INSERT INTO quotes (quote, author)
SELECT * FROM (VALUES
    ('The only way to do great work is to love what you do.', 'Steve Jobs'),
    ('Innovation distinguishes between a leader and a follower.', 'Steve Jobs'),
    ('Life is what happens when you''re busy making other plans.', 'John Lennon'),
    ('The future belongs to those who believe in the beauty of their dreams.', 'Eleanor Roosevelt'),
    ('It is during our darkest moments that we must focus to see the light.', 'Aristotle'),
    ('The only impossible journey is the one you never begin.', 'Tony Robbins'),
    ('In the middle of difficulty lies opportunity.', 'Albert Einstein'),
    ('Success is not final, failure is not fatal: it is the courage to continue that counts.', 'Winston Churchill'),
    ('Be yourself; everyone else is already taken.', 'Oscar Wilde'),
    ('Believe you can and you''re halfway there.', 'Theodore Roosevelt')
) AS new_quotes
WHERE NOT EXISTS (SELECT 1 FROM quotes LIMIT 1);
EOSQL

echo "Database initialization complete!"

# Configure PostgreSQL to accept connections from VPC
docker exec postgres bash -c "echo 'host all all 10.0.0.0/16 md5' >> /var/lib/postgresql/data/pg_hba.conf"
docker restart postgres

echo "VM initialization complete!"
