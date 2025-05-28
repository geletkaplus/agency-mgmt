#!/usr/bin/env python
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
sys.path.insert(0, os.path.abspath('.'))
django.setup()

from django.db import connection

print("🔍 Checking migration records in database...\n")

# Check what migrations Django thinks are applied
with connection.cursor() as cursor:
    cursor.execute("SELECT * FROM django_migrations WHERE app='agency' ORDER BY id")
    migrations = cursor.fetchall()
    
    print("Migrations recorded in database:")
    for migration in migrations:
        print(f"  ID: {migration[0]}, App: {migration[1]}, Name: {migration[2]}, Applied: {migration[3]}")

print("\n🔍 Looking for problematic migration...")
problematic = None
for migration in migrations:
    if '0010_alter_monthlycost' in migration[2]:
        problematic = migration
        print(f"❌ Found problematic migration: {migration[2]}")
        break

if problematic:
    print("\n⚠️  To remove this migration record, run:")
    print(f"python manage.py dbshell")
    print(f"DELETE FROM django_migrations WHERE id={problematic[0]};")
    print(".exit")
    print("\nOr run this Python script to do it automatically:")
    
    response = input("\nDo you want to remove this migration record? (y/N): ")
    if response.lower() == 'y':
        with connection.cursor() as cursor:
            cursor.execute(f"DELETE FROM django_migrations WHERE id={problematic[0]}")
            print("✅ Problematic migration record removed!")
            print("\nNow you can run: python manage.py migrate")
else:
    print("✅ No problematic migration found in database")

# Check if there are any pending migrations
print("\n🔍 Checking for actual migration files that need to be applied...")
import os
migration_dir = 'agency_management/agency/migrations'
migration_files = [f for f in os.listdir(migration_dir) if f.endswith('.py') and f != '__init__.py']
migration_files.sort()

print(f"\nMigration files found: {migration_files}")

# Get the last applied migration
if migrations:
    last_applied = migrations[-1][2]
    print(f"\nLast applied migration: {last_applied}")
