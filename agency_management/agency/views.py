# agency/views.py - Fixed with proper forecast revenue calculation
from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.db.models import Sum, Q, Count, F
from django.contrib.auth.decorators import login_required
from django.utils import timezone
from datetime import datetime, date
from decimal import Decimal
import json
import calendar

# Import only models that exist
from .models import (
    Company, UserProfile, Client, Project, ProjectAllocation, 
    MonthlyRevenue, Expense, ContractorExpense, Cost, CapacitySnapshot
)

def calculate_monthly_operating_costs(company, year, month):
    """Calculate total operating costs for a specific month"""
    total_costs = Decimal('0')
    
    # 1. Calculate payroll costs from team members
    team_members = UserProfile.objects.filter(
        company=company, 
        status__in=['full_time', 'part_time']
    ).filter(
        Q(start_date__lte=date(year, month, 1)) | Q(start_date__isnull=True)
    ).filter(
        Q(end_date__gte=date(year, month, 1)) | Q(end_date__isnull=True)
    )
    
    for member in team_members:
        total_costs += member.monthly_salary_cost
    
    # 2. Try to get costs from Cost model if it exists
    try:
        # Get costs active during this month
        month_start = date(year, month, 1)
        month_end = date(year, month, calendar.monthrange(year, month)[1])
        
        costs_this_month = Cost.objects.filter(
            company=company,
            start_date__lte=month_end,
            is_active=True
        ).filter(
            Q(end_date__isnull=True) | Q(end_date__gte=month_start)
        )
        
        for cost in costs_this_month:
            # Don't double-count payroll
            if cost.cost_type != 'payroll':
                total_costs += cost.monthly_amount
    except:
        # If Cost model doesn't exist, use legacy models
        # Legacy Expense model
        expenses = Expense.objects.filter(
            company=company, 
            is_active=True,
            start_date__lte=month_end
        ).filter(
            Q(end_date__isnull=True) | Q(end_date__gte=month_start)
        )
        for expense in expenses:
            total_costs += expense.monthly_amount
        
        # Legacy ContractorExpense model
        contractor_expenses = ContractorExpense.objects.filter(
            company=company, 
            year=year, 
            month=month
        )
        for expense in contractor_expenses:
            total_costs += expense.amount
    
    return total_costs

@login_required
def dashboard(request):
    """Enhanced dashboard with comprehensive metrics"""
    try:
        company = Company.objects.first()
        if not company:
            # Create default company if none exists
            company = Company.objects.create(name="Default Company", code="DC")
        
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Basic metrics
        total_clients = Client.objects.filter(company=company, status='active').count()
        total_projects = Project.objects.filter(company=company).count()
        
        # Check if revenue_type field exists on Project model
        try:
            booked_projects = Project.objects.filter(company=company, revenue_type='booked').count()
            forecast_projects = Project.objects.filter(company=company, revenue_type='forecast').count()
        except:
            # If revenue_type doesn't exist yet, just count all projects
            booked_projects = total_projects
            forecast_projects = 0
        
        total_team_members = UserProfile.objects.filter(company=company, status='full_time').count()
        
        # Current month revenue - calculate from both sources
        current_revenue = Decimal('0')
        
        # First try MonthlyRevenue table
        monthly_rev = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            month=current_month,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        if monthly_rev > 0:
            current_revenue = monthly_rev
        else:
            # Calculate from projects if no monthly revenue
            projects = Project.objects.filter(
                company=company,
                revenue_type='booked',
                start_date__lte=date(current_year, current_month, 28),
                end_date__gte=date(current_year, current_month, 1)
            )
            for project in projects:
                # Simple calculation - divide total by project duration in months
                duration_months = ((project.end_date.year - project.start_date.year) * 12 + 
                                 project.end_date.month - project.start_date.month + 1)
                if duration_months > 0:
                    current_revenue += project.total_revenue / duration_months
        
        # Annual revenue - properly calculate from both booked and forecast
        annual_booked_revenue = Decimal('0')
        annual_forecast_revenue = Decimal('0')
        
        # Try MonthlyRevenue first
        monthly_booked = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        monthly_forecast = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='forecast'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        if monthly_booked > 0 or monthly_forecast > 0:
            annual_booked_revenue = monthly_booked
            annual_forecast_revenue = monthly_forecast
        else:
            # Calculate from Projects
            for project in Project.objects.filter(company=company):
                try:
                    revenue_type = getattr(project, 'revenue_type', 'booked')
                except:
                    revenue_type = 'booked'
                
                # Calculate how much of this project falls in current year
                year_start = date(current_year, 1, 1)
                year_end = date(current_year, 12, 31)
                
                project_start = max(project.start_date, year_start)
                project_end = min(project.end_date, year_end)
                
                if project_start <= project_end:
                    # Project overlaps with current year
                    total_project_days = (project.end_date - project.start_date).days + 1
                    year_project_days = (project_end - project_start).days + 1
                    
                    if total_project_days > 0:
                        year_revenue = project.total_revenue * Decimal(year_project_days) / Decimal(total_project_days)
                        
                        if revenue_type == 'forecast':
                            annual_forecast_revenue += year_revenue
                        else:
                            annual_booked_revenue += year_revenue
        
        total_annual_revenue = annual_booked_revenue + annual_forecast_revenue
        
        # Monthly costs calculation
        payroll_costs = Decimal('0')
        contractor_costs = Decimal('0')
        other_costs = Decimal('0')
        
        # Calculate payroll costs from team members
        team_members = UserProfile.objects.filter(company=company, status='full_time')
        for member in team_members:
            payroll_costs += member.monthly_salary_cost
        
        # Try to get costs from Cost model if it exists
        try:
            costs_this_month = Cost.objects.filter(
                company=company,
                start_date__lte=date(current_year, current_month, 1),
                is_active=True
            ).filter(
                Q(end_date__isnull=True) | Q(end_date__gte=date(current_year, current_month, 1))
            )
            
            for cost in costs_this_month:
                cost_amount = cost.monthly_amount
                if cost.is_contractor:
                    contractor_costs += cost_amount
                elif cost.cost_type != 'payroll':
                    other_costs += cost_amount
        except:
            # If Cost model doesn't exist, use legacy models
            expenses = Expense.objects.filter(company=company, is_active=True)
            for expense in expenses:
                other_costs += expense.monthly_amount
            
            contractor_expenses = ContractorExpense.objects.filter(
                company=company, year=current_year, month=current_month
            )
            for expense in contractor_expenses:
                contractor_costs += expense.amount
        
        current_month_costs = payroll_costs + contractor_costs + other_costs
        
        # Annual costs
        total_annual_costs = current_month_costs * 12  # Simplified calculation
        
        # Profit calculations
        monthly_profit = current_revenue - current_month_costs
        monthly_profit_margin = (monthly_profit / current_revenue * 100) if current_revenue > 0 else Decimal('0')
        
        annual_profit = total_annual_revenue - total_annual_costs
        annual_profit_margin = (annual_profit / total_annual_revenue * 100) if total_annual_revenue > 0 else Decimal('0')
        
        context = {
            'company': company,
            'total_clients': total_clients,
            'total_projects': total_projects,
            'booked_projects': booked_projects,
            'forecast_projects': forecast_projects,
            'total_team_members': total_team_members,
            
            # Revenue metrics
            'current_revenue': current_revenue,
            'annual_booked_revenue': annual_booked_revenue,
            'annual_forecast_revenue': annual_forecast_revenue,
            'total_annual_revenue': total_annual_revenue,
            
            # Cost metrics
            'current_month_costs': current_month_costs,
            'payroll_costs': payroll_costs,
            'contractor_costs': contractor_costs,
            'other_costs': other_costs,
            'total_annual_costs': total_annual_costs,
            
            # Profit metrics
            'monthly_profit': monthly_profit,
            'monthly_profit_margin': monthly_profit_margin,
            'annual_profit': annual_profit,
            'annual_profit_margin': annual_profit_margin,
            
            'current_year': current_year,
            'current_month': current_month,
        }
        
        # Add all profiles for user switcher
        if request.user.is_superuser:
            context["all_profiles"] = UserProfile.objects.filter(
                company=company
            ).select_related("user").order_by("user__last_name", "user__first_name")

        return render(request, 'dashboard.html', context)
    
    except Exception as e:
        # Fallback context if anything fails
        context = {
            'error': str(e),
            'total_clients': 0,
            'total_projects': 0,
            'current_revenue': Decimal('0'),
            'total_annual_revenue': Decimal('0'),
            'current_month_costs': Decimal('0'),
            'monthly_profit': Decimal('0'),
        }
        # Add all profiles for user switcher
        if request.user.is_superuser:
            context["all_profiles"] = UserProfile.objects.filter(
                company=company
            ).select_related("user").order_by("user__last_name", "user__first_name")

        return render(request, 'dashboard.html', context)

@login_required
def revenue_chart_data(request):
    """API endpoint for revenue chart data - FIXED FORECAST CALCULATION"""
    company = Company.objects.first()
    if not company:
        return JsonResponse({
            'months': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
            'booked': [0] * 12,
            'forecast': [0] * 12,
            'combined': [0] * 12,
            'expenses': [0] * 12,
            'year': 2025,
            'error': 'No company found'
        })
    
    year = int(request.GET.get('year', datetime.now().year))
    
    # Initialize monthly data
    monthly_data = {}
    for month in range(1, 13):
        monthly_data[month] = {
            'booked': 0, 
            'forecast': 0,
            'expenses': 0
        }
    
    try:
        # Strategy 1: Get revenue from MonthlyRevenue table
        monthly_revenues = MonthlyRevenue.objects.filter(
            company=company,
            year=year
        ).values('month', 'revenue_type').annotate(total=Sum('revenue'))
        
        monthly_revenue_data_found = False
        for revenue in monthly_revenues:
            monthly_revenue_data_found = True
            month = revenue['month']
            revenue_type = revenue['revenue_type']
            total = float(revenue['total'])
            if month in monthly_data and revenue_type in ['booked', 'forecast']:
                monthly_data[month][revenue_type] = total
                print(f"MonthlyRevenue: {year}-{month:02d} {revenue_type}: ${total}")
        
        # Strategy 2: Calculate from Projects (always do this to catch all data)
        print(f"\nCalculating revenue from Projects for year {year}...")
        
        projects = Project.objects.filter(company=company)
        print(f"Total projects found: {projects.count()}")
        
        for project in projects:
            try:
                # Get revenue type
                revenue_type = 'booked'  # default
                if hasattr(project, 'revenue_type'):
                    revenue_type = project.revenue_type
                    print(f"\nProject: {project.name} - Type: {revenue_type} - Total: ${project.total_revenue}")
                
                # Only process if we have a valid revenue type
                if revenue_type not in ['booked', 'forecast']:
                    revenue_type = 'booked'
                
                # Calculate which months this project covers in the requested year
                year_start = date(year, 1, 1)
                year_end = date(year, 12, 31)
                
                # Find overlap between project dates and requested year
                overlap_start = max(project.start_date, year_start)
                overlap_end = min(project.end_date, year_end)
                
                if overlap_start <= overlap_end:
                    # Project has some overlap with the requested year
                    print(f"  Overlaps {year} from {overlap_start} to {overlap_end}")
                    
                    # Calculate monthly revenue for this project
                    total_project_months = 0
                    current_date = project.start_date.replace(day=1)
                    end_date = project.end_date.replace(day=1)
                    
                    while current_date <= end_date:
                        total_project_months += 1
                        if current_date.month == 12:
                            current_date = current_date.replace(year=current_date.year + 1, month=1)
                        else:
                            current_date = current_date.replace(month=current_date.month + 1)
                    
                    if total_project_months > 0:
                        monthly_amount = float(project.total_revenue) / total_project_months
                        print(f"  Monthly amount: ${monthly_amount:.2f} ({total_project_months} months)")
                        
                        # Now add this amount to each month in the overlap period
                        current_month = overlap_start.replace(day=1)
                        while current_month <= overlap_end:
                            if current_month.year == year:
                                month_num = current_month.month
                                monthly_data[month_num][revenue_type] += monthly_amount
                                print(f"  Added ${monthly_amount:.2f} to {year}-{month_num:02d} ({revenue_type})")
                            
                            # Move to next month
                            if current_month.month == 12:
                                current_month = current_month.replace(year=current_month.year + 1, month=1)
                            else:
                                current_month = current_month.replace(month=current_month.month + 1)
                else:
                    print(f"  No overlap with {year}")
                        
            except Exception as e:
                print(f"Error processing project {project.name}: {e}")
                continue
        
        # Calculate operating expenses for each month
        for month in range(1, 13):
            monthly_data[month]['expenses'] = float(
                calculate_monthly_operating_costs(company, year, month)
            )
        
    except Exception as e:
        print(f"Error in revenue_chart_data: {e}")
        import traceback
        traceback.print_exc()
    
    # Convert to lists for chart
    months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    booked_data = [monthly_data[i+1]['booked'] for i in range(12)]
    forecast_data = [monthly_data[i+1]['forecast'] for i in range(12)]
    combined_data = [monthly_data[i+1]['booked'] + monthly_data[i+1]['forecast'] for i in range(12)]
    expenses_data = [monthly_data[i+1]['expenses'] for i in range(12)]
    
    # Debug output
    print(f"\nFinal data for {year}:")
    print(f"Booked: {booked_data}")
    print(f"Forecast: {forecast_data}")
    print(f"Combined: {combined_data}")
    print(f"Expenses: {expenses_data}")
    
    response_data = {
        'months': months,
        'booked': booked_data,
        'forecast': forecast_data,
        'combined': combined_data,  # New field for stacked view
        'expenses': expenses_data,
        'year': year,
        'debug': {
            'company': company.name,
            'total_booked': sum(booked_data),
            'total_forecast': sum(forecast_data),
            'total_combined': sum(combined_data),
            'total_expenses': sum(expenses_data),
            'data_source': 'combined'  # We now always combine both sources
        }
    }
    
    return JsonResponse(response_data)

@login_required
def projects_list(request):
    """List all projects with revenue type filter"""
    company = Company.objects.first()
    revenue_type = request.GET.get('revenue_type', 'all')
    
    projects = Project.objects.filter(company=company).select_related('client')
    
    # Only filter by revenue_type if the field exists
    if revenue_type != 'all':
        try:
            projects = projects.filter(revenue_type=revenue_type)
        except:
            pass  # Field doesn't exist yet
    
    projects = projects.order_by('-created_at')
    
    context = {
        'projects': projects,
        'company': company,
        'current_filter': revenue_type,
    }
    
    return render(request, 'projects/list.html', context)

@login_required
def clients_list(request):
    """List all clients"""
    company = Company.objects.first()
    clients = Client.objects.filter(company=company).order_by('name')
    
    context = {
        'clients': clients,
        'company': company,
    }
    
    return render(request, 'clients/list.html', context)

@login_required
def team_list(request):
    """List all team members"""
    company = Company.objects.first()
    team_members = UserProfile.objects.filter(company=company).select_related('user').order_by('user__last_name')
    
    context = {
        'team_members': team_members,
        'company': company,
    }
    
    return render(request, 'team/list.html', context)

@login_required
def capacity_dashboard(request):
    """Capacity planning dashboard"""
    company = Company.objects.first()
    
    # Calculate current month utilization
    current_year = datetime.now().year
    current_month = datetime.now().month
    
    # Get team capacity
    team_members = UserProfile.objects.filter(company=company, status='full_time')
    total_capacity = sum(
        float(profile.weekly_capacity_hours) * 4.33 
        for profile in team_members
    )
    
    # Get current allocations
    current_allocations = ProjectAllocation.objects.filter(
        project__company=company,
        year=current_year,
        month=current_month
    ).aggregate(total=Sum('allocated_hours'))['total'] or 0
    
    utilization_rate = (float(current_allocations) / total_capacity * 100) if total_capacity > 0 else 0
    
    context = {
        'company': company,
        'total_capacity': total_capacity,
        'current_allocations': current_allocations,
        'utilization_rate': utilization_rate,
        'team_members': team_members,
    }
    
    return render(request, 'capacity.html', context)

def health_check(request):
    """Simple health check endpoint"""
    return JsonResponse({'status': 'ok', 'timestamp': datetime.now().isoformat()})

# Additional view stubs for URLs
def client_detail(request, client_id):
    """Client detail view"""
    return JsonResponse({'error': 'Not implemented yet'})

def project_detail(request, project_id):
    """Project detail view"""
    return JsonResponse({'error': 'Not implemented yet'})

def import_data(request):
    """Import data from spreadsheet"""
    return JsonResponse({'error': 'Not implemented yet'})

def capacity_chart_data(request):
    """API endpoint for capacity chart data"""
    return JsonResponse({'error': 'Not implemented yet'})

# Dashboard routing views
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
    """Admin dashboard with user switching"""
    return dashboard(request)  # Use existing dashboard

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
            'user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'managed_projects': managed_projects,
            'total_revenue_managed': total_revenue_managed,
            'active_projects': active_projects,
            'team_members': team_members_count,
            'total_allocated_hours': current_allocations,
            'projects_data': projects_data,
            'current_year': current_year,
            'current_month': current_month,
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
        
        # Get upcoming allocations
        upcoming_allocations = ProjectAllocation.objects.filter(
            user_profile=user_profile,
            year__gte=current_year,
            month__gt=current_month
        ).select_related('project', 'project__client').order_by('year', 'month')[:5]
        
        context = {
            'user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'allocated_projects': allocated_projects,
            'current_allocations': current_allocations,
            'total_hours_this_month': total_hours_this_month,
            'monthly_capacity': monthly_capacity,
            'utilization_rate': utilization_rate,
            'project_allocations': project_allocations,
            'historical_data': json.dumps(historical_data),
            'upcoming_allocations': upcoming_allocations,
            'current_year': current_year,
            'current_month': current_month,
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
    
    return redirect('agency:dashboard')

@login_required
def switch_back_to_admin(request):
    """Switch back to admin view"""
    if 'viewing_as_user' in request.session:
        del request.session['viewing_as_user']
    return redirect('agency:dashboard')
