# Add these imports at the top of views.py
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
