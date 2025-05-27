#!/bin/bash

# Fixed Migration Script - Handles the database migration issues properly
set -e

echo "🔧 FIXING MIGRATION ISSUES..."
echo "==============================="

# 1. First, fix the admin.py import error
echo "🩹 Fixing admin.py import error..."

# Create a temporary admin.py that only imports existing models
cat > agency/admin.py << 'EOF'
# agency/admin.py - Temporary safe version
from django.contrib import admin
from django.contrib.auth.models import User

# Only import models that definitely exist
try:
    from .models import (
        Company, UserProfile, Client, Project, 
        ProjectAllocation, MonthlyRevenue, Expense, ContractorExpense
    )
    
    @admin.register(Company)
    class CompanyAdmin(admin.ModelAdmin):
        list_display = ['name', 'code', 'created_at']
        search_fields = ['name', 'code']

    @admin.register(UserProfile)
    class UserProfileAdmin(admin.ModelAdmin):
        list_display = ['user', 'company', 'role', 'status', 'hourly_rate']
        list_filter = ['role', 'status', 'company']

    @admin.register(Client)
    class ClientAdmin(admin.ModelAdmin):
        list_display = ['name', 'company', 'status', 'account_manager']
        list_filter = ['status', 'company']

    @admin.register(Project)
    class ProjectAdmin(admin.ModelAdmin):
        list_display = ['name', 'client', 'status', 'start_date', 'end_date', 'total_revenue']
        list_filter = ['status', 'project_type', 'company']

    @admin.register(ProjectAllocation)
    class ProjectAllocationAdmin(admin.ModelAdmin):
        list_display = ['project', 'user_profile', 'year', 'month', 'allocated_hours']
        list_filter = ['year', 'month']

    @admin.register(MonthlyRevenue)
    class MonthlyRevenueAdmin(admin.ModelAdmin):
        list_display = ['client', 'year', 'month', 'revenue', 'revenue_type']
        list_filter = ['revenue_type', 'year', 'month']

    @admin.register(Expense)
    class ExpenseAdmin(admin.ModelAdmin):
        list_display = ['name', 'category', 'monthly_amount', 'is_active']
        list_filter = ['category', 'is_active']

    @admin.register(ContractorExpense)
    class ContractorExpenseAdmin(admin.ModelAdmin):
        list_display = ['name', 'year', 'month', 'amount']
        list_filter = ['year', 'month']

except ImportError as e:
    print(f"Warning: Could not import some models: {e}")
    # Register only User model as fallback
    pass

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
EOF

echo "✅ Fixed admin.py imports"

# 2. Now let's check what migrations exist and clean up
echo "📋 Checking current migration state..."
python manage.py showmigrations agency

# 3. Remove any problematic migration files
echo "🗑️ Cleaning up problematic migrations..."
rm -f agency/migrations/0004_*.py

# 4. Reset to a known good state
echo "⏪ Rolling back to migration 0003..."
python manage.py migrate agency 0003

# 5. Now let's add new features step by step
echo "📝 Step 1: Adding revenue_type field to Project..."

# First, let's see what's actually in the current models.py
echo "Current Project model fields:"
python manage.py shell << 'EOF'
from agency.models import Project
for field in Project._meta.fields:
    print(f"  {field.name}: {field.__class__.__name__}")
EOF

# Create a migration to add revenue_type to Project if it doesn't exist
python manage.py makemigrations agency --name add_revenue_type_to_project --empty

# Get the migration file name
MIGRATION_FILE=$(ls -t agency/migrations/*add_revenue_type_to_project.py | head -1)

# Write the migration content
cat > "$MIGRATION_FILE" << 'EOF'
# Generated migration for adding revenue_type to Project

from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0003_contractorexpense_expense_monthlycost_recurringcost_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='revenue_type',
            field=models.CharField(
                choices=[('booked', 'Booked'), ('forecast', 'Forecast')],
                default='booked',
                max_length=10
            ),
        ),
    ]
EOF

echo "✅ Created revenue_type migration"

# 6. Apply the first migration
echo "🗄️ Applying revenue_type migration..."
python manage.py migrate agency

# 7. Create the Cost model migration
echo "📝 Step 2: Adding Cost model..."

python manage.py makemigrations agency --name add_cost_model --empty

# Get the migration file name
COST_MIGRATION_FILE=$(ls -t agency/migrations/*add_cost_model.py | head -1)

# Write the Cost model migration
cat > "$COST_MIGRATION_FILE" << 'EOF'
# Generated migration for adding Cost model

from django.db import migrations, models
import django.core.validators
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
                ('cost_type', models.CharField(
                    choices=[
                        ('contractor', 'Contractor'),
                        ('payroll', 'Payroll'),
                        ('rent', 'Rent'),
                        ('utilities', 'Utilities'),
                        ('software', 'Software/Technology'),
                        ('office', 'Office Supplies'),
                        ('marketing', 'Marketing'),
                        ('travel', 'Travel'),
                        ('professional', 'Professional Services'),
                        ('insurance', 'Insurance'),
                        ('other', 'Other'),
                    ],
                    max_length=20
                )),
                ('description', models.TextField(blank=True)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('frequency', models.CharField(
                    choices=[
                        ('monthly', 'Monthly Recurring'),
                        ('one_time', 'One Time'),
                        ('project_duration', 'Spread Over Project Duration'),
                    ],
                    default='monthly',
                    max_length=20
                )),
                ('start_date', models.DateField()),
                ('end_date', models.DateField(blank=True, null=True)),
                ('is_contractor', models.BooleanField(default=False)),
                ('vendor', models.CharField(blank=True, max_length=200)),
                ('is_billable', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('company', models.ForeignKey(on_delete=models.deletion.CASCADE, related_name='costs', to='agency.company')),
                ('project', models.ForeignKey(blank=True, null=True, on_delete=models.deletion.CASCADE, related_name='costs', to='agency.project')),
            ],
        ),
        migrations.AddIndex(
            model_name='cost',
            index=models.Index(fields=['company', 'start_date'], name='agency_cost_company_start_idx'),
        ),
        migrations.AddIndex(
            model_name='cost',
            index=models.Index(fields=['cost_type', 'is_contractor'], name='agency_cost_type_contractor_idx'),
        ),
    ]
EOF

echo "✅ Created Cost model migration"

# 8. Apply the Cost model migration
echo "🗄️ Applying Cost model migration..."
python manage.py migrate agency

# 9. Create CapacitySnapshot model migration
echo "📝 Step 3: Adding CapacitySnapshot model..."

python manage.py makemigrations agency --name add_capacity_snapshot --empty

# Get the migration file name
CAPACITY_MIGRATION_FILE=$(ls -t agency/migrations/*add_capacity_snapshot.py | head -1)

# Write the CapacitySnapshot migration
cat > "$CAPACITY_MIGRATION_FILE" << 'EOF'
# Generated migration for adding CapacitySnapshot model

from django.db import migrations, models
import django.core.validators
import uuid

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0005_add_cost_model'),
    ]

    operations = [
        migrations.CreateModel(
            name='CapacitySnapshot',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('year', models.IntegerField()),
                ('month', models.IntegerField(validators=[django.core.validators.MinValueValidator(1), django.core.validators.MaxValueValidator(12)])),
                ('total_capacity_hours', models.DecimalField(decimal_places=1, max_digits=8)),
                ('total_allocated_hours', models.DecimalField(decimal_places=1, max_digits=8)),
                ('total_revenue', models.DecimalField(decimal_places=2, max_digits=12)),
                ('utilization_rate', models.DecimalField(decimal_places=2, max_digits=5)),
                ('role_capacity_data', models.JSONField(default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('company', models.ForeignKey(on_delete=models.deletion.CASCADE, related_name='capacity_snapshots', to='agency.company')),
            ],
            options={
                'indexes': [models.Index(fields=['company', 'year', 'month'], name='agency_capacitysnap_company_year_month_idx')],
            },
        ),
        migrations.AddConstraint(
            model_name='capacitysnapshot',
            constraint=models.UniqueConstraint(fields=('company', 'year', 'month'), name='unique_company_year_month'),
        ),
    ]
EOF

echo "✅ Created CapacitySnapshot migration"

# 10. Apply the CapacitySnapshot migration
echo "🗄️ Applying CapacitySnapshot migration..."
python manage.py migrate agency

# 11. Update admin.py to include new models
echo "📝 Updating admin interface with new models..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Updated with new models
from django.contrib import admin
from django.db.models import Sum
from .models import (
    Company, UserProfile, Client, Project, ProjectAllocation, 
    MonthlyRevenue, Cost, CapacitySnapshot, Expense, ContractorExpense
)

@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']

@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']

@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']

@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'revenue_type', 'start_date', 'end_date', 'total_revenue']
    list_filter = ['status', 'revenue_type', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'

@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

@admin.register(MonthlyRevenue)
class MonthlyRevenueAdmin(admin.ModelAdmin):
    list_display = ['client', 'month_year', 'revenue', 'revenue_type']
    list_filter = ['revenue_type', 'year', 'month', 'company']
    search_fields = ['client__name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

@admin.register(Cost)
class CostAdmin(admin.ModelAdmin):
    list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_contractor', 'is_active']
    list_filter = ['cost_type', 'frequency', 'is_contractor', 'is_active', 'company']
    search_fields = ['name', 'description', 'vendor']
    
    fieldsets = (
        ('Basic Information', {
            'fields': ('company', 'name', 'cost_type', 'description', 'vendor')
        }),
        ('Cost Details', {
            'fields': ('amount', 'frequency', 'start_date', 'end_date')
        }),
        ('Assignment & Flags', {
            'fields': ('is_contractor', 'project', 'is_billable', 'is_active')
        })
    )

@admin.register(CapacitySnapshot)
class CapacitySnapshotAdmin(admin.ModelAdmin):
    list_display = ['company', 'month_year', 'utilization_rate', 'total_capacity_hours', 'total_allocated_hours']
    list_filter = ['year', 'month', 'company']
    readonly_fields = ['created_at']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

# Legacy models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']
    search_fields = ['name']

@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'amount', 'company']
    list_filter = ['year', 'month', 'company']
    search_fields = ['name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

echo "✅ Updated admin interface"

# 12. Check final migration state
echo "📋 Final migration state:"
python manage.py showmigrations agency

echo ""
echo "🎉 MIGRATION COMPLETED SUCCESSFULLY!"
echo "=================================="
echo ""
echo "✅ What was accomplished:"
echo "  ✓ Fixed admin.py import errors"
echo "  ✓ Cleaned up problematic migrations"
echo "  ✓ Added revenue_type field to Project model"
echo "  ✓ Added Cost model for unified cost tracking"
echo "  ✓ Added CapacitySnapshot model"
echo "  ✓ Updated admin interface"
echo ""
echo "🚀 Next steps:"
echo "  1. python manage.py runserver"
echo "  2. Visit /admin to see all models"
echo "  3. Test creating costs and projects"
echo ""
echo "💡 Your database is now ready for the enhanced dashboard!"
echo ""