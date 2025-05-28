#!/bin/bash
echo "⚠️  WARNING: This will reset migrations. Make sure you have a backup!"
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Backing up current migrations..."
    mkdir -p migrations_backup
    cp agency_management/agency/migrations/*.py migrations_backup/
    
    echo "Removing migration files (keeping __init__.py)..."
    find agency_management/agency/migrations -name "*.py" -not -name "__init__.py" -delete
    find agency_management/agency/migrations -name "*.pyc" -delete
    
    echo "Creating fresh migrations..."
    python manage.py makemigrations agency
    
    echo "Done! Now you can run: python manage.py migrate --fake-initial"
fi
