#!/usr/bin/env python
"""
Complete working implementation for PM/Employee dashboards and allocation fixes
Run this script to implement all the features properly
"""

import os
import sys

print("🚀 Implementing Agency Management Dashboard Features...")
print("=" * 60)

# 1. First, let's add the is_project_manager field manually to the database
print("\n📝 Step 1: Adding is_project_manager field to database...")
add_field_sql = """
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.db import connection

with connection.cursor() as cursor:
    try:
        cursor.execute("ALTER TABLE agency_userprofile ADD COLUMN is_project_manager BOOLEAN DEFAULT 0 NOT NULL")
        print("✅ Field added to database")
    except Exception as e:
        if "duplicate column" in str(e).lower():
            print("✅ Field already exists in database")
        else:
            print(f"⚠️  {e}")
"""

with open('add_db_field.py', 'w') as f:
    f.write(add_field_sql)

os.system('python add_db_field.py')

# 2. Update views.py with all the dashboard views
print("\n📝 Step 2: Creating complete views update...")
views_content = '''# Add these imports at the top of views.py
from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
from django.db.models import Sum, Q, Count, F
from django.http import JsonResponse
from datetime import datetime, date
from decimal import Decimal
from django.contrib.auth.models import User

# Add these new views to your views.py

@login_required
def dashboard_router(request):
    """Route to appropriate dashboard based on user role"""
    # Check if superadmin is viewing as another user
    if request.user.is_superuser and 'viewing_as_user' in request.session:
        try:
            view_as_user = User.objects.get(id=request.session['viewing_as_user'])
            if hasattr(view_as_user, 'profile'):
                if view_as_user.profile.is_project_manager:
                    return redirect('agency:pm_dashboard')
                else:
                    return redirect('agency:employee_dashboard')
        except:
            pass
    
    # Normal routing
    if request.user.is_superuser:
        return redirect('agency:admin_dashboard')
    
    try:
        profile = request.user.profile
        if profile.is_project_manager:
            return redirect('agency:pm_dashboard')
        else:
            return redirect('agency:employee_dashboard')
    except:
        return redirect('agency:admin_dashboard')

def get_viewing_user(request):
    """Get the user we should display data for"""
    if request.user.is_superuser and 'viewing_as_user' in request.session:
        try:
            return User.objects.get(id=request.session['viewing_as_user'])
        except:
            pass
    return request.user

@login_required
def admin_dashboard(request):
    """Superadmin dashboard - your existing dashboard view"""
    # Add all_profiles to context for user switcher
    company = Company.objects.first()
    
    # Your existing dashboard code here...
    # Add this to context:
    all_profiles = UserProfile.objects.filter(
        company=company
    ).select_related('user').order_by('user__last_name', 'user__first_name')
    
    # Rest of your existing dashboard code...
    context = {
        # ... your existing context ...
        'all_profiles': all_profiles,
        'is_admin_view': True,
    }
    return render(request, 'dashboard.html', context)

@login_required
def pm_dashboard(request):
    """Project Manager Dashboard"""
    viewing_user = get_viewing_user(request)
    
    try:
        user_profile = viewing_user.profile
        company = user_profile.company
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Get projects where user is PM
        managed_projects = Project.objects.filter(
            project_manager=viewing_user,
            company=company
        ).select_related('client')
        
        # Calculate metrics
        total_revenue_managed = managed_projects.aggregate(
            total=Sum('total_revenue')
        )['total'] or Decimal('0')
        
        active_projects = managed_projects.filter(status='active').count()
        completed_projects = managed_projects.filter(status='completed').count()
        
        # Get unique team members across all projects
        team_members_ids = ProjectAllocation.objects.filter(
            project__in=managed_projects
        ).values_list('user_profile', flat=True).distinct()
        team_members_count = len(set(team_members_ids))
        
        # Current month allocations
        current_allocations = ProjectAllocation.objects.filter(
            project__in=managed_projects,
            year=current_year,
            month=current_month
        ).aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        
        # Project details with allocation status
        projects_data = []
        for project in managed_projects.filter(status__in=['active', 'planning']):
            allocated = project.allocations.aggregate(
                total=Sum('allocated_hours')
            )['total'] or Decimal('0')
            
            total_hours = project.total_hours or Decimal('0')
            utilization = (float(allocated) / float(total_hours) * 100) if total_hours > 0 else 0
            
            # Get team members for this project
            if hasattr(project, 'team_members'):
                team_size = project.team_members.count()
            else:
                team_size = project.allocations.values('user_profile').distinct().count()
            
            projects_data.append({
                'project': project,
                'allocated_hours': allocated,
                'utilization': utilization,
                'team_size': team_size,
                'health': 'good' if utilization >= 80 else 'warning' if utilization >= 50 else 'critical'
            })
        
        context = {
            'viewing_user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'managed_projects': managed_projects,
            'total_revenue_managed': total_revenue_managed,
            'active_projects': active_projects,
            'completed_projects': completed_projects,
            'team_members': team_members_count,
            'total_allocated_hours': current_allocations,
            'projects_data': projects_data,
            'current_year': current_year,
            'current_month': current_month,
            'is_pm': True,
            'viewing_as_user': request.session.get('viewing_as_user'),
        }
        
        return render(request, 'dashboards/pm_dashboard.html', context)
        
    except Exception as e:
        print(f"PM Dashboard Error: {e}")
        return redirect('agency:dashboard')

@login_required
def employee_dashboard(request):
    """Employee Dashboard"""
    viewing_user = get_viewing_user(request)
    
    try:
        user_profile = viewing_user.profile
        company = user_profile.company
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Get projects where user is allocated
        allocated_projects = Project.objects.filter(
            allocations__user_profile=user_profile
        ).distinct().select_related('client')
        
        # Current month allocations
        current_allocations = ProjectAllocation.objects.filter(
            user_profile=user_profile,
            year=current_year,
            month=current_month
        ).select_related('project', 'project__client')
        
        # Calculate totals
        total_hours_this_month = current_allocations.aggregate(
            total=Sum('allocated_hours')
        )['total'] or Decimal('0')
        
        monthly_capacity = user_profile.weekly_capacity_hours * Decimal('4.33')
        utilization_rate = (float(total_hours_this_month) / float(monthly_capacity) * 100) if monthly_capacity > 0 else 0
        
        # Project breakdown
        project_allocations = []
        for allocation in current_allocations:
            project_allocations.append({
                'project': allocation.project,
                'client': allocation.project.client,
                'hours': allocation.allocated_hours,
                'value': allocation.allocated_hours * allocation.hourly_rate
            })
        
        # Historical data (last 6 months)
        historical_data = []
        for i in range(6):
            month = current_month - i
            year = current_year
            if month <= 0:
                month += 12
                year -= 1
            
            month_hours = ProjectAllocation.objects.filter(
                user_profile=user_profile,
                year=year,
                month=month
            ).aggregate(total=Sum('allocated_hours'))['total'] or 0
            
            historical_data.append({
                'month': month,
                'year': year,
                'hours': float(month_hours),
                'utilization': (float(month_hours) / float(monthly_capacity) * 100) if monthly_capacity > 0 else 0
            })
        
        historical_data.reverse()
        
        context = {
            'viewing_user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'allocated_projects': allocated_projects,
            'current_allocations': current_allocations,
            'total_hours_this_month': total_hours_this_month,
            'monthly_capacity': monthly_capacity,
            'utilization_rate': utilization_rate,
            'project_allocations': project_allocations,
            'historical_data': json.dumps(historical_data),
            'current_year': current_year,
            'current_month': current_month,
            'is_employee': True,
            'viewing_as_user': request.session.get('viewing_as_user'),
        }
        
        return render(request, 'dashboards/employee_dashboard.html', context)
        
    except Exception as e:
        print(f"Employee Dashboard Error: {e}")
        return redirect('agency:dashboard')

@login_required
def switch_user_view(request):
    """Allow superadmin to switch to another user's view"""
    if not request.user.is_superuser:
        return JsonResponse({'error': 'Unauthorized'}, status=403)
    
    user_id = request.GET.get('user_id')
    if user_id:
        request.session['viewing_as_user'] = user_id
        return redirect('agency:dashboard_router')
    
    return redirect('agency:admin_dashboard')

@login_required
def switch_back_to_admin(request):
    """Switch back to admin view"""
    if 'viewing_as_user' in request.session:
        del request.session['viewing_as_user']
    return redirect('agency:admin_dashboard')
'''

with open('views_update.py', 'w') as f:
    f.write(views_content)

print("✅ Created views_update.py - Copy these functions to your views.py")

# 3. Fix the allocation save in admin.py
print("\n📝 Step 3: Creating allocation save fix...")
allocation_fix = '''# Replace the save_allocations_view method in ProjectAdmin with this:

def save_allocations_view(self, request, object_id):
    """Handle allocation saves via AJAX - FIXED VERSION"""
    if request.method == 'POST':
        try:
            project = self.get_object(request, object_id)
            data = json.loads(request.body)
            allocations = data.get('allocations', [])
            
            # Log what we received
            print(f"Received {len(allocations)} allocation entries")
            
            # Clear existing allocations
            ProjectAllocation.objects.filter(project=project).delete()
            
            # Process allocations
            monthly_totals = {}
            for alloc in allocations:
                member_id = alloc.get('member_id') or alloc.get('user_profile')
                year = int(alloc.get('year', 0))
                month = int(alloc.get('month', 0))
                hours = float(alloc.get('hours', 0))
                
                if member_id and year and month and hours > 0:
                    key = (str(member_id), year, month)
                    if key not in monthly_totals:
                        monthly_totals[key] = 0
                    monthly_totals[key] += hours
            
            # Create allocations
            created_count = 0
            for (member_id, year, month), hours in monthly_totals.items():
                try:
                    member = UserProfile.objects.get(id=member_id)
                    ProjectAllocation.objects.create(
                        project=project,
                        user_profile=member,
                        year=year,
                        month=month,
                        allocated_hours=Decimal(str(hours)),
                        hourly_rate=member.hourly_rate
                    )
                    created_count += 1
                except Exception as e:
                    print(f"Error creating allocation: {e}")
            
            return JsonResponse({
                'status': 'success',
                'message': f'Created {created_count} allocations'
            })
            
        except Exception as e:
            import traceback
            print(f"Allocation save error: {e}")
            print(traceback.format_exc())
            return JsonResponse({
                'status': 'error',
                'message': str(e)
            }, status=500)
    
    return JsonResponse({
        'status': 'error',
        'message': 'Invalid request method'
    }, status=400)
'''

with open('admin_allocation_fix.py', 'w') as f:
    f.write(allocation_fix)

print("✅ Created admin_allocation_fix.py - Copy this to your admin.py")

# 4. Create URL updates
print("\n📝 Step 4: Creating URL configuration...")
urls_update = '''# Add these URL patterns to your agency/urls.py:

from django.urls import path
from . import views

urlpatterns = [
    # Dashboard routing
    path('', views.dashboard_router, name='dashboard_router'),
    path('dashboard/', views.admin_dashboard, name='dashboard'),  # Your existing dashboard
    path('admin-dashboard/', views.admin_dashboard, name='admin_dashboard'),
    path('pm-dashboard/', views.pm_dashboard, name='pm_dashboard'),
    path('employee-dashboard/', views.employee_dashboard, name='employee_dashboard'),
    
    # User switching
    path('switch-user/', views.switch_user_view, name='switch_user'),
    path('switch-back/', views.switch_back_to_admin, name='switch_back'),
    
    # ... your other URLs ...
]
'''

with open('urls_update.txt', 'w') as f:
    f.write(urls_update)

print("✅ Created urls_update.txt - Add these patterns to your urls.py")

# 5. Create template updates
print("\n📝 Step 5: Creating template updates...")

# Update main dashboard
dashboard_update = '''<!-- Add this to your dashboard.html in the header section after company name -->

{% if user.is_superuser and all_profiles %}
<div class="ml-4">
    <select id="userSwitcher" class="border border-gray-300 rounded-md px-3 py-2 text-sm"
            onchange="if(this.value) window.location.href='/agency/switch-user/?user_id=' + this.value">
        <option value="">View as User...</option>
        {% for profile in all_profiles %}
        <option value="{{ profile.user.id }}">
            {{ profile.user.get_full_name|default:profile.user.username }} 
            ({{ profile.get_role_display }}{% if profile.is_project_manager %} - PM{% endif %})
        </option>
        {% endfor %}
    </select>
</div>
{% endif %}
'''

with open('dashboard_header_update.html', 'w') as f:
    f.write(dashboard_update)

print("✅ Created dashboard_header_update.html - Add this to your dashboard.html")

# 6. Create a test script
print("\n📝 Step 6: Creating test script...")
test_script = '''import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from agency.models import UserProfile, Project
from django.contrib.auth.models import User

print("🧪 Testing Dashboard Implementation...")

# 1. Check if is_project_manager field exists
try:
    pm_count = UserProfile.objects.filter(is_project_manager=True).count()
    print(f"✅ is_project_manager field works! Found {pm_count} PMs")
except Exception as e:
    print(f"❌ is_project_manager field error: {e}")

# 2. Set some users as PMs
print("\\nSetting up test project managers...")
profiles = UserProfile.objects.filter(role__in=['leadership', 'account'])[:2]
for profile in profiles:
    profile.is_project_manager = True
    profile.save()
    print(f"✅ Made {profile.user.get_full_name()} a project manager")

# 3. Assign PMs to projects
print("\\nAssigning PMs to projects...")
projects = Project.objects.all()[:3]
pm_users = [p.user for p in UserProfile.objects.filter(is_project_manager=True)]
for i, project in enumerate(projects):
    if pm_users:
        project.project_manager = pm_users[i % len(pm_users)]
        project.save()
        print(f"✅ Assigned {project.project_manager.get_full_name()} to {project.name}")

print("\\n✅ Test setup complete!")
print("\\nYou can now:")
print("1. Login as superadmin")
print("2. Use the dropdown to switch to a PM or employee view")
print("3. PMs will see their managed projects")
print("4. Employees will see their allocated hours")
'''

with open('test_dashboards.py', 'w') as f:
    f.write(test_script)

print("✅ Created test_dashboards.py")

# 7. Create implementation checklist
print("\n📝 Creating implementation checklist...")
checklist = '''# Implementation Checklist

## 1. Database Field
- [ ] Run: python add_db_field.py
- [ ] Verify field exists: python manage.py shell
      >>> from agency.models import UserProfile
      >>> UserProfile._meta.get_field('is_project_manager')

## 2. Models.py
- [ ] Add to UserProfile class:
      is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")

## 3. Views.py
- [ ] Copy all functions from views_update.py to your views.py
- [ ] Import json at the top: import json

## 4. URLs.py
- [ ] Add URL patterns from urls_update.txt

## 5. Admin.py
- [ ] Replace save_allocations_view with the version from admin_allocation_fix.py
- [ ] Add datetime import at top: import datetime

## 6. Templates
- [ ] Create folder: templates/dashboards/
- [ ] Copy pm_dashboard.html and employee_dashboard.html from previous artifact
- [ ] Update dashboard.html with user switcher from dashboard_header_update.html

## 7. Static Files
- [ ] Make sure you have Chart.js loaded in your base template

## 8. Test
- [ ] Run: python test_dashboards.py
- [ ] Login as superadmin
- [ ] Test user switching dropdown
- [ ] Test PM dashboard shows managed projects
- [ ] Test employee dashboard shows allocations
- [ ] Test allocation saving in project admin

## 9. Assign Users
- [ ] In Django Admin > User Profiles:
      - Check "Is project manager" for PMs
- [ ] In Django Admin > Projects:
      - Assign Project Managers
      - Add team members
      - Test allocation grid
'''

with open('IMPLEMENTATION_CHECKLIST.md', 'w') as f:
    f.write(checklist)

print("✅ Created IMPLEMENTATION_CHECKLIST.md")

print("\n" + "="*60)
print("✅ Implementation files created!")
print("\nFollow IMPLEMENTATION_CHECKLIST.md to implement all features.")
print("\nKey files created:")
print("- views_update.py (dashboard views)")
print("- admin_allocation_fix.py (fixes save allocations)")
print("- urls_update.txt (URL patterns)")
print("- dashboard_header_update.html (user switcher)")
print("- test_dashboards.py (test the implementation)")
print("\nStart with: python add_db_field.py")