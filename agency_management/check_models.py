#!/usr/bin/env python
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
sys.path.insert(0, os.path.abspath('.'))
django.setup()

from agency.models import *

print("🔍 Checking Models...")
print("\nModels found:")
for model in [Company, UserProfile, Client, Project, ProjectAllocation, MonthlyRevenue, Cost, CapacitySnapshot, Expense, ContractorExpense]:
    try:
        print(f"✓ {model.__name__}: {model.objects.count()} records")
        if hasattr(model, '_meta'):
            fields = [f.name for f in model._meta.get_fields()]
            print(f"  Fields: {', '.join(fields[:5])}{'...' if len(fields) > 5 else ''}")
    except Exception as e:
        print(f"✗ {model.__name__}: Error - {str(e)}")

print("\n🔍 Checking for MonthlyCost and RecurringCost models...")
try:
    from agency.models import MonthlyCost
    print("⚠️  MonthlyCost model still exists in models.py - this should be removed!")
except ImportError:
    print("✓ MonthlyCost model not found (good)")

try:
    from agency.models import RecurringCost
    print("⚠️  RecurringCost model still exists in models.py - this should be removed!")
except ImportError:
    print("✓ RecurringCost model not found (good)")

print("\n🔍 Checking Project model fields...")
try:
    project_fields = [f.name for f in Project._meta.get_fields()]
    if 'billable_rate' in project_fields:
        print("✓ Project has billable_rate field")
    else:
        print("⚠️  Project missing billable_rate field")
    
    if 'calculated_hours' in project_fields:
        print("✓ Project has calculated_hours field")
    else:
        print("⚠️  Project missing calculated_hours field")
        
    if 'team_members' in project_fields:
        print("✓ Project has team_members field")
    else:
        print("⚠️  Project missing team_members field")
except Exception as e:
    print(f"Error checking Project fields: {e}")

print("\n✅ Diagnostic complete!")
