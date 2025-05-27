#!/usr/bin/env python
"""
Debug and fix Django migration issues
Run this from your Django project root: python debug_migrations.py
"""

import os
import sys
import django
from django.core.management import call_command
from django.db import connection

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

def check_tables():
    """Check which tables exist in the database"""
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        print("\n=== Current tables in database ===")
        for table in tables:
            print(f"  - {table[0]}")
        return [table[0] for table in tables]

def check_migrations():
    """Check migration status"""
    print("\n=== Migration Status ===")
    from django.core.management import call_command
    call_command('showmigrations', 'agency')

def check_migration_files():
    """Check what migration files exist"""
    print("\n=== Migration Files ===")
    migration_dir = 'agency/migrations'
    if os.path.exists(migration_dir):
        files = sorted([f for f in os.listdir(migration_dir) if f.endswith('.py') and not f.startswith('__')])
        for f in files:
            print(f"  - {f}")
    else:
        print("  Migration directory not found!")

def create_cost_migration():
    """Create the Cost model migration manually"""
    print("\n=== Creating Cost Migration ===")
    
    migration_content = '''# Generated manually for Cost model

from django.db import migrations, models
import django.db.models.deletion
import uuid

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0004_add_revenue_type_to_project'),
    ]

    operations = [
        migrations.CreateModel(
            name='Cost',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=200)),
                ('cost_type', models.CharField(choices=[('contractor', 'Contractor'), ('payroll', 'Payroll'), ('rent', 'Rent'), ('utilities', 'Utilities'), ('software', 'Software/Technology'), ('office', 'Office Supplies'), ('marketing', 'Marketing'), ('travel', 'Travel'), ('professional', 'Professional Services'), ('insurance', 'Insurance'), ('other', 'Other')], max_length=20)),
                ('description', models.TextField(blank=True)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('frequency', models.CharField(choices=[('monthly', 'Monthly Recurring'), ('one_time', 'One Time'), ('project_duration', 'Spread Over Project Duration')], default='monthly', max_length=20)),
                ('start_date', models.DateField()),
                ('end_date', models.DateField(blank=True, null=True)),
                ('is_contractor', models.BooleanField(default=False)),
                ('vendor', models.CharField(blank=True, max_length=200)),
                ('is_billable', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('company', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.company')),
                ('project', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.project')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['company', 'start_date'], name='agency_cost_company_start_idx'),
                    models.Index(fields=['cost_type', 'is_contractor'], name='agency_cost_type_contractor_idx'),
                ],
            },
        ),
    ]
'''
    
    # Ensure migrations directory exists
    os.makedirs('agency/migrations', exist_ok=True)
    
    # Write migration file
    migration_path = 'agency/migrations/0005_cost.py'
    with open(migration_path, 'w') as f:
        f.write(migration_content)
    
    print(f"  Created: {migration_path}")

def apply_migrations():
    """Apply migrations"""
    print("\n=== Applying Migrations ===")
    try:
        call_command('migrate', 'agency')
        print("  Migrations applied successfully!")
    except Exception as e:
        print(f"  Error applying migrations: {e}")
        return False
    return True

def create_table_manually():
    """Create the agency_cost table manually if migrations fail"""
    print("\n=== Creating agency_cost table manually ===")
    
    create_table_sql = '''
    CREATE TABLE IF NOT EXISTS agency_cost (
        id VARCHAR(36) PRIMARY KEY,
        name VARCHAR(200) NOT NULL,
        cost_type VARCHAR(20) NOT NULL,
        description TEXT,
        amount DECIMAL(10, 2) NOT NULL,
        frequency VARCHAR(20) DEFAULT 'monthly',
        start_date DATE NOT NULL,
        end_date DATE,
        is_contractor BOOLEAN DEFAULT 0,
        vendor VARCHAR(200),
        is_billable BOOLEAN DEFAULT 0,
        is_active BOOLEAN DEFAULT 1,
        created_at DATETIME NOT NULL,
        company_id VARCHAR(36) NOT NULL,
        project_id VARCHAR(36),
        FOREIGN KEY (company_id) REFERENCES agency_company(id),
        FOREIGN KEY (project_id) REFERENCES agency_project(id)
    );
    '''
    
    try:
        with connection.cursor() as cursor:
            cursor.execute(create_table_sql)
        print("  Table created successfully!")
        
        # Also create the indexes
        index_sqls = [
            "CREATE INDEX IF NOT EXISTS agency_cost_company_start_idx ON agency_cost (company_id, start_date);",
            "CREATE INDEX IF NOT EXISTS agency_cost_type_contractor_idx ON agency_cost (cost_type, is_contractor);"
        ]
        
        with connection.cursor() as cursor:
            for idx_sql in index_sqls:
                cursor.execute(idx_sql)
        print("  Indexes created successfully!")
        
        return True
    except Exception as e:
        print(f"  Error creating table: {e}")
        return False

def main():
    print("Django Migration Debugger")
    print("=" * 50)
    
    # 1. Check current tables
    tables = check_tables()
    
    # 2. Check if agency_cost exists
    if 'agency_cost' in tables:
        print("\n✓ The agency_cost table already exists!")
        return
    
    # 3. Check migration files
    check_migration_files()
    
    # 4. Check migration status
    check_migrations()
    
    # 5. Create migration if needed
    if not os.path.exists('agency/migrations/0005_cost.py'):
        create_cost_migration()
    
    # 6. Try to apply migrations
    if apply_migrations():
        # Check if table was created
        tables = check_tables()
        if 'agency_cost' in tables:
            print("\n✓ Success! The agency_cost table has been created.")
        else:
            print("\n⚠ Migration applied but table not created. Creating manually...")
            if create_table_manually():
                print("\n✓ Table created manually!")
    else:
        print("\n⚠ Migration failed. Creating table manually...")
        if create_table_manually():
            print("\n✓ Table created manually!")
    
    # Final check
    tables = check_tables()
    if 'agency_cost' in tables:
        print("\n✓ COMPLETE: The agency_cost table now exists!")
        print("\nYou can now access: http://127.0.0.1:8000/admin/agency/cost/")
    else:
        print("\n✗ ERROR: Could not create the agency_cost table.")
        print("Please check your database permissions and Django settings.")

if __name__ == '__main__':
    main()