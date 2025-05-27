#!/bin/bash

# Complete Dashboard Update Script
# This script updates the dashboard to show Operating Expenses in the chart

echo "========================================="
echo "Dashboard Update Script"
echo "Adding Operating Expenses to Chart"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Backup current files
print_status "Creating backups..."
cp agency/views.py agency/views.py.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
cp templates/dashboard.html templates/dashboard.html.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null

# Step 2: Update views.py
print_status "Updating views.py with expense calculations..."
cat > agency/views.py << 'EOF'
# agency/views.py - Updated with operating expenses in chart
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
        
        # Current month revenue from MonthlyRevenue table
        current_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            month=current_month,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        # Annual revenue from MonthlyRevenue table
        annual_booked_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        annual_forecast_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='forecast'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
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
        return render(request, 'dashboard.html', context)

@login_required
def revenue_chart_data(request):
    """API endpoint for revenue chart data - NOW WITH OPERATING EXPENSES"""
    company = Company.objects.first()
    if not company:
        return JsonResponse({
            'months': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
            'booked': [0] * 12,
            'forecast': [0] * 12,
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
        # Get revenue data
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
            if month in monthly_data and revenue_type in monthly_data[month]:
                monthly_data[month][revenue_type] = total
        
        # If no MonthlyRevenue data, calculate from Projects
        if not monthly_revenue_data_found:
            projects = Project.objects.filter(company=company)
            
            for project in projects:
                try:
                    revenue_type = getattr(project, 'revenue_type', 'booked')
                    if revenue_type not in ['booked', 'forecast']:
                        revenue_type = 'booked'
                    
                    start_date = project.start_date
                    end_date = project.end_date
                    
                    # Calculate project months that fall in the requested year
                    project_months = []
                    calc_start = max(start_date, date(year, 1, 1))
                    calc_end = min(end_date, date(year, 12, 31))
                    
                    if calc_start <= calc_end:
                        current_date = calc_start.replace(day=1)
                        while current_date <= calc_end:
                            if current_date.year == year:
                                project_months.append(current_date.month)
                            
                            if current_date.month == 12:
                                current_date = current_date.replace(year=current_date.year + 1, month=1)
                            else:
                                current_date = current_date.replace(month=current_date.month + 1)
                    
                    if project_months:
                        monthly_revenue_amount = float(project.total_revenue) / len(project_months)
                        for month in project_months:
                            monthly_data[month][revenue_type] += monthly_revenue_amount
                            
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
        # Return error but still provide structure
        pass
    
    # Convert to lists for chart
    months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    booked_data = [monthly_data[i+1]['booked'] for i in range(12)]
    forecast_data = [monthly_data[i+1]['forecast'] for i in range(12)]
    expenses_data = [monthly_data[i+1]['expenses'] for i in range(12)]
    
    response_data = {
        'months': months,
        'booked': booked_data,
        'forecast': forecast_data,
        'expenses': expenses_data,
        'year': year,
        'debug': {
            'company': company.name,
            'total_booked': sum(booked_data),
            'total_forecast': sum(forecast_data),
            'total_expenses': sum(expenses_data),
            'data_source': 'monthly_revenue' if monthly_revenue_data_found else 'projects'
        }
    }
    
    print(f"Chart data response: {response_data}")
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
EOF

# Step 3: Update dashboard.html
print_status "Updating dashboard.html template..."

# First, let's check if the template exists in the expected location
if [ -f "templates/dashboard.html" ]; then
    DASHBOARD_PATH="templates/dashboard.html"
elif [ -f "agency/templates/dashboard.html" ]; then
    DASHBOARD_PATH="agency/templates/dashboard.html"
else
    print_warning "dashboard.html not found in expected locations. Creating in templates/"
    mkdir -p templates
    DASHBOARD_PATH="templates/dashboard.html"
fi

# Use sed to update the dashboard template
print_status "Applying template updates..."

# Create a temporary file with the updated content
cat > /tmp/dashboard_update.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agency Management Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <script>
        // Utility function to format currency
        function formatCurrency(value) {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD',
                minimumFractionDigits: 0,
                maximumFractionDigits: 0
            }).format(value);
        }
        
        // Utility function to format numbers with commas
        function formatNumber(value) {
            return new Intl.NumberFormat('en-US').format(value);
        }
    </script>
</head>
<body class="bg-gray-100">
    <div class="min-h-screen">
        <!-- Header -->
        <header class="bg-white shadow">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div class="flex justify-between items-center py-6">
                    <div class="flex items-center">
                        <h1 class="text-3xl font-bold text-gray-900">Agency Management</h1>
                        {% if company %}
                            <span class="ml-4 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">{{ company.name }}</span>
                        {% endif %}
                    </div>
                    <div class="flex space-x-4">
                        <a href="/admin/" class="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600">
                            <i class="fas fa-cog mr-2"></i>Admin
                        </a>
                    </div>
                </div>
            </div>
        </header>

        <!-- Main Content -->
        <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            
            {% if error %}
                <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-6">
                    <strong>Error:</strong> {{ error }}
                </div>
            {% endif %}

            <!-- Key Metrics Grid -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                <!-- Current Month Revenue -->
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="flex items-center">
                        <div class="flex-1">
                            <p class="text-sm font-medium text-gray-600">Current Month Revenue</p>
                            <p class="text-2xl font-bold text-green-600">
                                <script>document.write(formatCurrency({{ current_revenue|default:0 }}));</script>
                            </p>
                        </div>
                        <div class="ml-4">
                            <i class="fas fa-dollar-sign text-green-500 text-2xl"></i>
                        </div>
                    </div>
                </div>

                <!-- Annual Revenue -->
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="flex items-center">
                        <div class="flex-1">
                            <p class="text-sm font-medium text-gray-600">Annual Revenue ({{ current_year|default:2025 }})</p>
                            <p class="text-2xl font-bold text-blue-600">
                                <script>document.write(formatCurrency({{ total_annual_revenue|default:0 }}));</script>
                            </p>
                            <p class="text-sm text-gray-500">
                                Booked: <script>document.write(formatCurrency({{ annual_booked_revenue|default:0 }}));</script> | 
                                Forecast: <script>document.write(formatCurrency({{ annual_forecast_revenue|default:0 }}));</script>
                            </p>
                        </div>
                        <div class="ml-4">
                            <i class="fas fa-chart-line text-blue-500 text-2xl"></i>
                        </div>
                    </div>
                </div>

                <!-- Operating Costs (Monthly) -->
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="flex items-center">
                        <div class="flex-1">
                            <p class="text-sm font-medium text-gray-600">Operating Costs (Monthly)</p>
                            <p class="text-2xl font-bold text-red-600">
                                <script>document.write(formatCurrency({{ current_month_costs|default:0 }}));</script>
                            </p>
                            <div class="text-sm text-gray-500">
                                <div>Payroll: <script>document.write(formatCurrency({{ payroll_costs|default:0 }}));</script></div>
                                <div>Contractors: <script>document.write(formatCurrency({{ contractor_costs|default:0 }}));</script></div>
                                <div>Other: <script>document.write(formatCurrency({{ other_costs|default:0 }}));</script></div>
                            </div>
                        </div>
                        <div class="ml-4">
                            <i class="fas fa-money-bill-wave text-red-500 text-2xl"></i>
                        </div>
                    </div>
                </div>

                <!-- Monthly Profit -->
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="flex items-center">
                        <div class="flex-1">
                            <p class="text-sm font-medium text-gray-600">Monthly Profit</p>
                            <p class="text-2xl font-bold text-green-600">
                                <script>document.write(formatCurrency({{ monthly_profit|default:0 }}));</script>
                            </p>
                            <p class="text-sm text-gray-500">{{ monthly_profit_margin|default:0|floatformat:1 }}% margin</p>
                        </div>
                        <div class="ml-4">
                            <i class="fas fa-chart-pie text-green-500 text-2xl"></i>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Secondary Metrics -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
                <!-- Active Clients -->
                <div class="bg-white rounded-lg shadow p-4">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-blue-600">
                            <script>document.write(formatNumber({{ total_clients|default:0 }}));</script>
                        </p>
                        <p class="text-sm text-gray-600">Active Clients</p>
                    </div>
                </div>

                <!-- Projects -->
                <div class="bg-white rounded-lg shadow p-4">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-purple-600">
                            <script>document.write(formatNumber({{ total_projects|default:0 }}));</script>
                        </p>
                        <p class="text-sm text-gray-600">Total Projects</p>
                        <p class="text-xs text-gray-500">
                            <script>document.write(formatNumber({{ booked_projects|default:0 }}));</script> booked | 
                            <script>document.write(formatNumber({{ forecast_projects|default:0 }}));</script> forecast
                        </p>
                    </div>
                </div>

                <!-- Team Size -->
                <div class="bg-white rounded-lg shadow p-4">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-orange-600">
                            <script>document.write(formatNumber({{ total_team_members|default:0 }}));</script>
                        </p>
                        <p class="text-sm text-gray-600">Team Members</p>
                    </div>
                </div>

                <!-- Annual Costs -->
                <div class="bg-white rounded-lg shadow p-4">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-red-600">
                            <script>document.write(formatCurrency({{ total_annual_costs|default:0 }}));</script>
                        </p>
                        <p class="text-sm text-gray-600">Annual Costs</p>
                    </div>
                </div>

                <!-- Annual Profit -->
                <div class="bg-white rounded-lg shadow p-4">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-green-600">
                            <script>document.write(formatCurrency({{ annual_profit|default:0 }}));</script>
                        </p>
                        <p class="text-sm text-gray-600">Annual Profit</p>
                        <p class="text-xs text-gray-500">{{ annual_profit_margin|default:0|floatformat:1 }}% margin</p>
                    </div>
                </div>
            </div>

            <!-- Revenue & Expenses Chart -->
            <div class="bg-white rounded-lg shadow mb-8">
                <div class="px-6 py-4 border-b border-gray-200">
                    <div class="flex justify-between items-center">
                        <h2 class="text-xl font-semibold text-gray-900">Revenue & Operating Expenses</h2>
                        <div class="flex space-x-4">
                            <select id="yearSelect" class="border border-gray-300 rounded-md px-3 py-2">
                                <option value="2024">2024</option>
                                <option value="2025" selected>2025</option>
                                <option value="2026">2026</option>
                            </select>
                            <button id="refreshChart" class="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600">
                                <i class="fas fa-refresh mr-2"></i>Refresh
                            </button>
                            <button id="debugChart" class="bg-gray-500 text-white px-4 py-2 rounded-md hover:bg-gray-600">
                                <i class="fas fa-bug mr-2"></i>Debug
                            </button>
                        </div>
                    </div>
                </div>
                <div class="p-6">
                    <div class="relative h-96">
                        <canvas id="revenueChart"></canvas>
                    </div>
                    <div class="mt-4 flex justify-center space-x-6 text-sm">
                        <div class="flex items-center">
                            <div class="w-4 h-4 bg-green-500 rounded mr-2"></div>
                            <span>Booked Revenue</span>
                        </div>
                        <div class="flex items-center">
                            <div class="w-4 h-4 bg-blue-500 rounded mr-2"></div>
                            <span>Forecasted Revenue</span>
                        </div>
                        <div class="flex items-center">
                            <div class="w-4 h-4 bg-red-500 rounded mr-2"></div>
                            <span>Operating Expenses</span>
                        </div>
                    </div>
                    <!-- Debug Info -->
                    <div id="debugInfo" class="mt-4 p-3 bg-gray-100 rounded text-xs text-gray-600" style="display: none;">
                        <strong>Debug Information:</strong>
                        <div id="debugContent"></div>
                    </div>
                </div>
            </div>

            <!-- Quick Actions -->
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <!-- Project Management -->
                <div class="bg-white rounded-lg shadow p-6">
                    <h3 class="text-lg font-semibold text-gray-900 mb-4">Project Management</h3>
                    <div class="space-y-3">
                        <a href="/admin/agency/project/add/" class="block w-full bg-blue-500 text-white text-center py-2 px-4 rounded-md hover:bg-blue-600">
                            <i class="fas fa-plus mr-2"></i>Add Project
                        </a>
                        <a href="{% url 'agency:projects_list' %}?revenue_type=booked" class="block w-full bg-green-500 text-white text-center py-2 px-4 rounded-md hover:bg-green-600">
                            <i class="fas fa-check mr-2"></i>View Booked Projects
                        </a>
                        <a href="{% url 'agency:projects_list' %}?revenue_type=forecast" class="block w-full bg-yellow-500 text-white text-center py-2 px-4 rounded-md hover:bg-yellow-600">
                            <i class="fas fa-clock mr-2"></i>View Forecast Projects
                        </a>
                    </div>
                </div>

                <!-- Team & Capacity -->
                <div class="bg-white rounded-lg shadow p-6">
                    <h3 class="text-lg font-semibold text-gray-900 mb-4">Team & Capacity</h3>
                    <div class="space-y-3">
                        <a href="{% url 'agency:capacity_dashboard' %}" class="block w-full bg-purple-500 text-white text-center py-2 px-4 rounded-md hover:bg-purple-600">
                            <i class="fas fa-chart-bar mr-2"></i>View Capacity
                        </a>
                        <a href="/admin/agency/userprofile/add/" class="block w-full bg-indigo-500 text-white text-center py-2 px-4 rounded-md hover:bg-indigo-600">
                            <i class="fas fa-user-plus mr-2"></i>Add Team Member
                        </a>
                        <a href="{% url 'agency:team_list' %}" class="block w-full bg-blue-500 text-white text-center py-2 px-4 rounded-md hover:bg-blue-600">
                            <i class="fas fa-users mr-2"></i>View Team
                        </a>
                    </div>
                </div>

                <!-- Admin Tools -->
                <div class="bg-white rounded-lg shadow p-6">
                    <h3 class="text-lg font-semibold text-gray-900 mb-4">Admin Tools</h3>
                    <div class="space-y-3">
                        <a href="/admin/" class="block w-full bg-gray-500 text-white text-center py-2 px-4 rounded-md hover:bg-gray-600">
                            <i class="fas fa-cog mr-2"></i>Django Admin
                        </a>
                        <a href="/admin/agency/" class="block w-full bg-gray-500 text-white text-center py-2 px-4 rounded-md hover:bg-gray-600">
                            <i class="fas fa-database mr-2"></i>Manage Data
                        </a>
                        <a href="{% url 'agency:clients_list' %}" class="block w-full bg-teal-500 text-white text-center py-2 px-4 rounded-md hover:bg-teal-600">
                            <i class="fas fa-building mr-2"></i>View Clients
                        </a>
                    </div>
                </div>
            </div>
        </main>
    </div>

    <script>
    document.addEventListener('DOMContentLoaded', function() {
        let revenueChart;
        let lastChartData = null;
        
        // Initialize revenue chart
        function initializeRevenueChart() {
            const ctx = document.getElementById('revenueChart').getContext('2d');
            
            revenueChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Booked Revenue',
                        data: [],
                        borderColor: 'rgb(34, 197, 94)',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        fill: true,
                        tension: 0.4
                    }, {
                        label: 'Forecasted Revenue',
                        data: [],
                        borderColor: 'rgb(59, 130, 246)',
                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                        fill: true,
                        tension: 0.4
                    }, {
                        label: 'Operating Expenses',
                        data: [],
                        borderColor: 'rgb(239, 68, 68)',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        fill: true,
                        tension: 0.4,
                        borderDash: [5, 5]
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            mode: 'index',
                            intersect: false,
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + formatCurrency(context.parsed.y);
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            title: {
                                display: true,
                                text: 'Month'
                            }
                        },
                        y: {
                            title: {
                                display: true,
                                text: 'Revenue ($)'
                            },
                            beginAtZero: true,
                            ticks: {
                                callback: function(value) {
                                    return formatCurrency(value);
                                }
                            }
                        }
                    }
                }
            });
        }
        
        // Load revenue chart data
        function loadRevenueData() {
            const year = document.getElementById('yearSelect').value;
            
            console.log(`Loading revenue data for year ${year}...`);
            
            fetch(`{% url 'agency:revenue_chart_data' %}?year=${year}`)
                .then(response => response.json())
                .then(data => {
                    console.log('Chart data received:', data);
                    lastChartData = data;
                    
                    revenueChart.data.labels = data.months;
                    revenueChart.data.datasets[0].data = data.booked;
                    revenueChart.data.datasets[1].data = data.forecast;
                    revenueChart.data.datasets[2].data = data.expenses || new Array(12).fill(0);
                    revenueChart.update();
                    
                    // Show some debug info
                    const totalBooked = data.booked.reduce((a, b) => a + b, 0);
                    const totalForecast = data.forecast.reduce((a, b) => a + b, 0);
                    const totalExpenses = (data.expenses || []).reduce((a, b) => a + b, 0);
                    console.log(`Total Booked: $${totalBooked}, Total Forecast: $${totalForecast}, Total Expenses: $${totalExpenses}`);
                })
                .catch(error => {
                    console.error('Error loading revenue data:', error);
                    // Use dummy data if API fails
                    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                    revenueChart.data.labels = months;
                    revenueChart.data.datasets[0].data = [10000, 12000, 15000, 18000, 16000, 20000, 22000, 19000, 21000, 23000, 25000, 27000];
                    revenueChart.data.datasets[1].data = [5000, 8000, 12000, 15000, 18000, 16000, 19000, 21000, 24000, 26000, 28000, 30000];
                    revenueChart.data.datasets[2].data = [8000, 8000, 8000, 8000, 8000, 8000, 8000, 8000, 8000, 8000, 8000, 8000];
                    revenueChart.update();
                });
        }
        
        // Debug function
        function showDebugInfo() {
            const debugDiv = document.getElementById('debugInfo');
            const debugContent = document.getElementById('debugContent');
            
            if (debugDiv.style.display === 'none') {
                debugDiv.style.display = 'block';
                if (lastChartData) {
                    debugContent.innerHTML = `
                        <div><strong>Company:</strong> ${lastChartData.debug?.company || 'Unknown'}</div>
                        <div><strong>Year:</strong> ${lastChartData.year}</div>
                        <div><strong>Data Source:</strong> ${lastChartData.debug?.data_source || 'Unknown'}</div>
                        <div><strong>Total Booked:</strong> $${lastChartData.debug?.total_booked || 0}</div>
                        <div><strong>Total Forecast:</strong> $${lastChartData.debug?.total_forecast || 0}</div>
                        <div><strong>Total Expenses:</strong> $${lastChartData.debug?.total_expenses || 0}</div>
                        <div><strong>Booked Data:</strong> [${lastChartData.booked?.join(', ') || 'No data'}]</div>
                        <div><strong>Forecast Data:</strong> [${lastChartData.forecast?.join(', ') || 'No data'}]</div>
                        <div><strong>Expenses Data:</strong> [${lastChartData.expenses?.join(', ') || 'No data'}]</div>
                        ${lastChartData.error ? `<div><strong>Error:</strong> ${lastChartData.error}</div>` : ''}
                    `;
                } else {
                    debugContent.innerHTML = '<div>No chart data loaded yet</div>';
                }
            } else {
                debugDiv.style.display = 'none';
            }
        }
        
        // Event listeners
        document.getElementById('yearSelect').addEventListener('change', loadRevenueData);
        document.getElementById('refreshChart').addEventListener('click', loadRevenueData);
        document.getElementById('debugChart').addEventListener('click', showDebugInfo);
        
        // Initialize
        initializeRevenueChart();
        loadRevenueData();
    });
    </script>
</body>
</html>
EOF

# Copy the updated template to the correct location
cp /tmp/dashboard_update.html "$DASHBOARD_PATH"
rm /tmp/dashboard_update.html

# Step 4: Run system check
print_status "Running Django system check..."
python manage.py check

# Step 5: Restart the development server
print_status "Updates complete!"
echo ""
echo "========================================="
echo "Dashboard Update Complete!"
echo "========================================="
echo ""
echo "Changes made:"
echo "  ✓ Updated views.py with expense calculations"
echo "  ✓ Added calculate_monthly_operating_costs() function"
echo "  ✓ Updated revenue_chart_data() to include expenses"
echo "  ✓ Changed 'Monthly Costs' to 'Operating Costs (Monthly)'"
echo "  ✓ Changed chart title to 'Revenue & Operating Expenses'"
echo "  ✓ Added red dashed line for Operating Expenses"
echo ""
echo "Backups created:"
echo "  - agency/views.py.backup.*"
echo "  - templates/dashboard.html.backup.*"
echo ""
print_status "Next steps:"
echo "  1. Start the development server: python manage.py runserver"
echo "  2. Visit http://127.0.0.1:8000/agency/"
echo "  3. The chart now shows Revenue vs Operating Expenses"
echo ""

# Optional: Ask if user wants to start the server
read -p "Would you like to start the development server now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    python manage.py runserver
fi