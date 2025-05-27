#!/bin/bash

# Comprehensive Agency Management Migration Script
# This script will:
# 1. Clean up cost models
# 2. Add project revenue type filter
# 3. Update dashboard with enhanced metrics
# 4. Add number formatting

set -e  # Exit on any error

echo "🚀 Starting Agency Management Migration..."
echo "============================================"

# Backup existing files
echo "📦 Creating backups..."
mkdir -p backups/$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"

cp agency/models.py "$BACKUP_DIR/models.py.backup"
cp agency/admin.py "$BACKUP_DIR/admin.py.backup"
cp agency/views.py "$BACKUP_DIR/views.py.backup"
cp templates/dashboard.html "$BACKUP_DIR/dashboard.html.backup" 2>/dev/null || echo "  Note: dashboard.html not found, will create new one"

echo "✅ Backups created in $BACKUP_DIR"

# 1. UPDATE MODELS.PY
echo "📝 Updating models.py with unified Cost model and Project revenue type..."

cat > agency/models.py << 'EOF'
# agency/models.py - Updated with unified Cost model
from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MinValueValidator, MaxValueValidator
from decimal import Decimal
import uuid

class Company(models.Model):
    """Company entity - supports multi-company setup"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=10, unique=True)  # e.g., "G+"
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name_plural = "Companies"
    
    def __str__(self):
        return f"{self.name} ({self.code})"

class UserProfile(models.Model):
    """Extended profile for users"""
    ROLE_CHOICES = [
        ('account', 'Account Management'),
        ('creative', 'Creative'),
        ('tech', 'Technology'),
        ('media', 'Media'),
        ('leadership', 'Leadership'),
        ('operations', 'Operations'),
    ]
    
    STATUS_CHOICES = [
        ('full_time', 'Full Time'),
        ('part_time', 'Part Time'),
        ('contractor', 'Contractor'),
        ('inactive', 'Inactive'),
    ]
    
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='user_profiles')
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='tech')
    hourly_rate = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal('50.00'))
    annual_salary = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='full_time')
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    weekly_capacity_hours = models.DecimalField(max_digits=4, decimal_places=1, default=40)
    utilization_target = models.DecimalField(max_digits=4, decimal_places=1, default=80)
    
    def __str__(self):
        return f"{self.user.get_full_name()} ({self.role})"
    
    @property
    def monthly_capacity_hours(self):
        """Calculate monthly capacity based on weekly capacity"""
        return (self.weekly_capacity_hours * Decimal('4.33'))  # Average weeks per month
    
    @property
    def monthly_salary_cost(self):
        """Calculate monthly salary cost"""
        if self.annual_salary:
            return self.annual_salary / 12
        return self.hourly_rate * self.weekly_capacity_hours * Decimal('4.33')

class Client(models.Model):
    """Client organizations"""
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('inactive', 'Inactive'),
        ('prospect', 'Prospect'),
        ('churned', 'Churned'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='clients')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    account_manager = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                                      related_name='managed_clients')
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return self.name

class Project(models.Model):
    """Projects for clients - UPDATED with revenue type"""
    STATUS_CHOICES = [
        ('planning', 'Planning'),
        ('active', 'Active'),
        ('on_hold', 'On Hold'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]
    
    TYPE_CHOICES = [
        ('retainer', 'Retainer'),
        ('project', 'Project'),
        ('hourly', 'Hourly'),
    ]
    
    REVENUE_TYPE_CHOICES = [
        ('booked', 'Booked'),
        ('forecast', 'Forecast'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name='projects')
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='projects')
    
    # Timing
    start_date = models.DateField()
    end_date = models.DateField()
    
    # Financial
    total_revenue = models.DecimalField(max_digits=12, decimal_places=2)
    total_hours = models.DecimalField(max_digits=8, decimal_places=1)
    project_type = models.CharField(max_length=20, choices=TYPE_CHOICES, default='project')
    revenue_type = models.CharField(max_length=10, choices=REVENUE_TYPE_CHOICES, default='booked')  # NEW
    
    # Status and management
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='planning')
    project_manager = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                                      related_name='managed_projects')
    
    # Metadata
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"{self.client.name} - {self.name}"
    
    @property
    def average_hourly_rate(self):
        """Calculate average hourly rate for the project"""
        if self.total_hours > 0:
            return self.total_revenue / self.total_hours
        return Decimal('0')

class ProjectAllocation(models.Model):
    """Monthly allocation of users to projects"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='allocations')
    user_profile = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='project_allocations')
    
    # Time allocation
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    allocated_hours = models.DecimalField(max_digits=6, decimal_places=1, 
                                        validators=[MinValueValidator(Decimal('0.1'))])
    
    # Financial tracking
    hourly_rate = models.DecimalField(max_digits=8, decimal_places=2)
    
    class Meta:
        unique_together = ['project', 'user_profile', 'year', 'month']
        indexes = [
            models.Index(fields=['year', 'month']),
            models.Index(fields=['project', 'year', 'month']),
            models.Index(fields=['user_profile', 'year', 'month']),
        ]
    
    def __str__(self):
        return f"{self.user_profile.user.get_full_name()} - {self.project.name} ({self.year}/{self.month:02d})"
    
    @property
    def total_revenue(self):
        """Calculate revenue for this allocation"""
        return self.allocated_hours * self.hourly_rate

class MonthlyRevenue(models.Model):
    """Monthly revenue tracking (for both booked and forecasted)"""
    REVENUE_TYPE_CHOICES = [
        ('booked', 'Booked'),
        ('forecast', 'Forecast'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name='monthly_revenues')
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='monthly_revenues', 
                               null=True, blank=True)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='monthly_revenues')
    
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    revenue = models.DecimalField(max_digits=12, decimal_places=2)
    revenue_type = models.CharField(max_length=10, choices=REVENUE_TYPE_CHOICES, default='booked')
    
    class Meta:
        unique_together = ['client', 'project', 'year', 'month', 'revenue_type']
        indexes = [
            models.Index(fields=['year', 'month', 'revenue_type']),
            models.Index(fields=['company', 'year', 'month']),
        ]
    
    def __str__(self):
        project_name = self.project.name if self.project else "General"
        return f"{self.client.name} - {project_name} ({self.year}/{self.month:02d}) - ${self.revenue}"

class Cost(models.Model):
    """Unified cost model for all expenses - NEW"""
    COST_TYPE_CHOICES = [
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
    ]
    
    FREQUENCY_CHOICES = [
        ('monthly', 'Monthly Recurring'),
        ('one_time', 'One Time'),
        ('project_duration', 'Spread Over Project Duration'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='costs')
    
    # Basic info
    name = models.CharField(max_length=200)
    cost_type = models.CharField(max_length=20, choices=COST_TYPE_CHOICES)
    description = models.TextField(blank=True)
    
    # Cost details
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    frequency = models.CharField(max_length=20, choices=FREQUENCY_CHOICES, default='monthly')
    
    # Time period
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    
    # Flags and assignment
    is_contractor = models.BooleanField(default=False)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='costs', 
                               null=True, blank=True)
    
    # Optional details
    vendor = models.CharField(max_length=200, blank=True)
    is_billable = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        indexes = [
            models.Index(fields=['company', 'start_date']),
            models.Index(fields=['cost_type', 'is_contractor']),
            models.Index(fields=['project', 'start_date']),
        ]
    
    def __str__(self):
        project_part = f" ({self.project.name})" if self.project else ""
        contractor_part = " [Contractor]" if self.is_contractor else ""
        return f"{self.name}{project_part}{contractor_part} - ${self.amount}"
    
    @property
    def monthly_amount(self):
        """Calculate monthly amount based on frequency"""
        if self.frequency == 'monthly':
            return self.amount
        elif self.frequency == 'one_time':
            return self.amount
        elif self.frequency == 'project_duration' and self.project:
            if self.start_date and self.end_date:
                months = (self.end_date.year - self.start_date.year) * 12 + (self.end_date.month - self.start_date.month) + 1
                return self.amount / months if months > 0 else self.amount
        return self.amount

class MonthlyCostSummary(models.Model):
    """Pre-calculated monthly cost summaries"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='monthly_cost_summaries')
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    
    # Calculated totals
    payroll_costs = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    contractor_costs = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    other_costs = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total_costs = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    
    last_calculated = models.DateTimeField(auto_now=True)
    
    class Meta:
        unique_together = ['company', 'year', 'month']
    
    def __str__(self):
        return f"{self.company.name} Costs ({self.year}-{self.month:02d}) - ${self.total_costs}"

class CapacitySnapshot(models.Model):
    """Monthly capacity snapshots for reporting and analytics"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='capacity_snapshots')
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    
    # Aggregated capacity metrics
    total_capacity_hours = models.DecimalField(max_digits=8, decimal_places=1)
    total_allocated_hours = models.DecimalField(max_digits=8, decimal_places=1)
    total_revenue = models.DecimalField(max_digits=12, decimal_places=2)
    utilization_rate = models.DecimalField(max_digits=5, decimal_places=2)  # Percentage
    
    # By role breakdown (stored as JSON)
    role_capacity_data = models.JSONField(default=dict)
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        unique_together = ['company', 'year', 'month']
        indexes = [
            models.Index(fields=['company', 'year', 'month']),
        ]
    
    def __str__(self):
        return f"{self.company.name} Capacity ({self.year}/{self.month:02d}) - {self.utilization_rate}%"

# Legacy models - keeping for compatibility during migration
class Expense(models.Model):
    """Legacy expense model"""
    CATEGORY_CHOICES = [
        ('rent', 'Rent'),
        ('utilities', 'Utilities'),
        ('technology', 'Technology'),
        ('marketing', 'Marketing'),
        ('travel', 'Travel'),
        ('office', 'Office Supplies'),
        ('professional', 'Professional Services'),
        ('other', 'Other'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='expenses')
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default='other')
    monthly_amount = models.DecimalField(max_digits=10, decimal_places=2)
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    
    def __str__(self):
        return f"{self.name} - ${self.monthly_amount}/month"

class ContractorExpense(models.Model):
    """Legacy contractor expense model"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='contractor_expenses')
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    description = models.TextField(blank=True)
    
    class Meta:
        unique_together = ['name', 'company', 'year', 'month']
    
    def __str__(self):
        return f"{self.name} ({self.year}/{self.month:02d}) - ${self.amount}"
EOF

echo "✅ Updated models.py with unified Cost model and Project revenue type"

# 2. UPDATE ADMIN.PY
echo "📝 Updating admin.py..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Updated for new models
from django.contrib import admin
from django.db.models import Sum
from django.utils.html import format_html
from .models import (
    Company, UserProfile, Client, Project, ProjectAllocation, 
    MonthlyRevenue, Cost, MonthlyCostSummary, CapacitySnapshot,
    Expense, ContractorExpense
)

@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']
    readonly_fields = ['created_at']

@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate', 'annual_salary']
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
    search_fields = ['project__name', 'user_profile__user__first_name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = 'Month'

@admin.register(MonthlyRevenue)
class MonthlyRevenueAdmin(admin.ModelAdmin):
    list_display = ['client', 'month_year', 'revenue', 'revenue_type']
    list_filter = ['revenue_type', 'year', 'month', 'company']
    search_fields = ['client__name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = 'Month'

@admin.register(Cost)
class CostAdmin(admin.ModelAdmin):
    list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_contractor', 'project', 'is_active']
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

@admin.register(MonthlyCostSummary)
class MonthlyCostSummaryAdmin(admin.ModelAdmin):
    list_display = ['company', 'month_year', 'payroll_costs', 'contractor_costs', 'other_costs', 'total_costs']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = 'Month'

@admin.register(CapacitySnapshot)
class CapacitySnapshotAdmin(admin.ModelAdmin):
    list_display = ['company', 'month_year', 'total_capacity_hours', 'utilization_rate']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = 'Month'

# Legacy models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'company', 'is_active']

@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'amount']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = 'Month'

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

echo "✅ Updated admin.py"

# 3. UPDATE VIEWS.PY
echo "📝 Updating views.py with enhanced dashboard metrics..."

cat > agency/views.py << 'EOF'
# agency/views.py - Updated with enhanced dashboard
from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
from django.contrib.admin.views.decorators import staff_member_required
from django.contrib import messages
from django.http import JsonResponse
from django.db.models import Sum, Count, Q
from django.core.management import call_command
from .models import (
    Company, Client, Project, MonthlyRevenue, UserProfile, 
    ProjectAllocation, Cost, MonthlyCostSummary
)
from datetime import datetime, date
from decimal import Decimal
import os

@login_required
def dashboard(request):
    """Enhanced dashboard with comprehensive metrics"""
    company = Company.objects.first()
    current_year = datetime.now().year
    current_month = datetime.now().month
    
    # Basic metrics
    total_clients = Client.objects.filter(company=company, status='active').count()
    total_projects = Project.objects.filter(company=company).count()
    booked_projects = Project.objects.filter(company=company, revenue_type='booked').count()
    forecast_projects = Project.objects.filter(company=company, revenue_type='forecast').count()
    total_team_members = UserProfile.objects.filter(company=company, status='full_time').count()
    
    # Current month revenue
    current_revenue = MonthlyRevenue.objects.filter(
        company=company,
        year=current_year,
        month=current_month,
        revenue_type='booked'
    ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
    
    # Annual revenue (YTD)
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
    current_month_costs = Decimal('0')
    payroll_costs = Decimal('0')
    contractor_costs = Decimal('0')
    other_costs = Decimal('0')
    
    # Calculate payroll costs
    team_members = UserProfile.objects.filter(company=company, status='full_time')
    for member in team_members:
        payroll_costs += member.monthly_salary_cost
    
    # Calculate other costs from Cost model
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
    
    current_month_costs = payroll_costs + contractor_costs + other_costs
    
    # Annual costs
    annual_payroll = payroll_costs * 12
    annual_other_costs = Decimal('0')
    
    # Estimate annual other costs (simplified)
    annual_other_costs = (contractor_costs + other_costs) * 12
    total_annual_costs = annual_payroll + annual_other_costs
    
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

def clients_list(request):
    """List all clients"""
    company = Company.objects.first()
    clients = Client.objects.filter(company=company).order_by('name')
    
    context = {
        'clients': clients,
        'company': company,
    }
    
    return render(request, 'clients/list.html', context)

def projects_list(request):
    """List all projects with revenue type filter"""
    company = Company.objects.first()
    revenue_type = request.GET.get('revenue_type', 'all')
    
    projects = Project.objects.filter(company=company).select_related('client')
    
    if revenue_type != 'all':
        projects = projects.filter(revenue_type=revenue_type)
    
    projects = projects.order_by('-created_at')
    
    context = {
        'projects': projects,
        'company': company,
        'current_filter': revenue_type,
    }
    
    return render(request, 'projects/list.html', context)

def team_list(request):
    """List all team members"""
    company = Company.objects.first()
    team_members = UserProfile.objects.filter(company=company).select_related('user').order_by('user__last_name')
    
    context = {
        'team_members': team_members,
        'company': company,
    }
    
    return render(request, 'team/list.html', context)

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

@staff_member_required
def import_data(request):
    """Import data from spreadsheet"""
    if request.method == 'POST':
        file_path = request.POST.get('file_path')
        company_code = request.POST.get('company_code', 'G+')
        
        if file_path and os.path.exists(file_path):
            try:
                call_command('import_spreadsheet', file_path, company_code)
                messages.success(request, f'Successfully imported data from {file_path}')
            except Exception as e:
                messages.error(request, f'Import failed: {str(e)}')
        else:
            messages.error(request, 'File path not found')
        
        return redirect('agency:dashboard')
    
    context = {
        'title': 'Import Spreadsheet Data'
    }
    return render(request, 'import_data.html', context)

@login_required
def revenue_chart_data(request):
    """API endpoint for revenue chart data"""
    company = Company.objects.first()
    year = int(request.GET.get('year', datetime.now().year))
    
    # Get monthly revenue data
    revenues = MonthlyRevenue.objects.filter(
        company=company,
        year=year
    ).values('month', 'revenue_type').annotate(
        total=Sum('revenue')
    ).order_by('month', 'revenue_type')
    
    # Format data for chart
    monthly_data = {}
    for month in range(1, 13):
        monthly_data[month] = {'booked': 0, 'forecast': 0}
    
    for revenue in revenues:
        month = revenue['month']
        revenue_type = revenue['revenue_type']
        total = float(revenue['total'])
        monthly_data[month][revenue_type] = total
    
    # Convert to lists for chart
    months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    booked_data = [monthly_data[i+1]['booked'] for i in range(12)]
    forecast_data = [monthly_data[i+1]['forecast'] for i in range(12)]
    
    return JsonResponse({
        'months': months,
        'booked': booked_data,
        'forecast': forecast_data,
        'year': year
    })

@login_required
def capacity_chart_data(request):
    """API endpoint for capacity chart data"""
    company = Company.objects.first()
    year = int(request.GET.get('year', datetime.now().year))
    
    # Get all team members for capacity calculation
    team_members = UserProfile.objects.filter(company=company, status='full_time')
    
    # Calculate monthly data
    months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    
    capacity_hours = []
    booked_hours = []
    projected_hours = []
    
    for month in range(1, 13):
        # Calculate total capacity for the month
        month_capacity = sum(
            float(profile.weekly_capacity_hours) * 4.33  # Average weeks per month
            for profile in team_members
        )
        capacity_hours.append(month_capacity)
        
        # Get allocations for active projects (booked)
        booked_allocations = ProjectAllocation.objects.filter(
            project__company=company,
            project__status='active',
            year=year,
            month=month
        ).aggregate(total=Sum('allocated_hours'))['total'] or 0
        booked_hours.append(float(booked_allocations))
        
        # Get allocations for active + planning projects (projected)
        projected_allocations = ProjectAllocation.objects.filter(
            project__company=company,
            project__status__in=['active', 'planning'],
            year=year,
            month=month
        ).aggregate(total=Sum('allocated_hours'))['total'] or 0
        projected_hours.append(float(projected_allocations))
    
    return JsonResponse({
        'months': months,
        'capacity_hours': capacity_hours,
        'booked_hours': booked_hours,
        'projected_hours': projected_hours,
        'year': year
    })

# Additional views for future features
def client_detail(request, client_id):
    """Client detail view"""
    company = Company.objects.first()
    client = Client.objects.get(id=client_id, company=company)
    
    projects = Project.objects.filter(client=client).order_by('-created_at')
    revenues = MonthlyRevenue.objects.filter(
        client=client,
        year=datetime.now().year
    ).order_by('month')
    
    context = {
        'client': client,
        'projects': projects,
        'revenues': revenues,
        'company': company,
    }
    
    return render(request, 'clients/detail.html', context)

def project_detail(request, project_id):
    """Project detail view"""
    company = Company.objects.first()
    project = Project.objects.get(id=project_id, company=company)
    
    allocations = ProjectAllocation.objects.filter(
        project=project
    ).select_related('user_profile__user').order_by('year', 'month')
    
    # Group allocations by month
    monthly_allocations = {}
    for allocation in allocations:
        month_key = f"{allocation.year}-{allocation.month:02d}"
        if month_key not in monthly_allocations:
            monthly_allocations[month_key] = []
        monthly_allocations[month_key].append(allocation)
    
    context = {
        'project': project,
        'monthly_allocations': monthly_allocations,
        'company': company,
    }
    
    return render(request, 'projects/detail.html', context)

def health_check(request):
    """Simple health check endpoint"""
    return JsonResponse({'status': 'ok', 'timestamp': datetime.now().isoformat()})
EOF

echo "✅ Updated views.py with enhanced dashboard"

# 4. UPDATE DASHBOARD TEMPLATE
echo "📝 Creating enhanced dashboard template with number formatting..."

cat > templates/dashboard.html << 'EOF'
{% extends 'base.html' %}
{% load humanize %}

{% block title %}Dashboard - Agency Management{% endblock %}

{% block content %}
<div class="mb-8">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Dashboard</h1>
    <p class="text-gray-600">Overview of {{ company.name }}'s performance and capacity</p>
</div>

<!-- Key Metrics Grid -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
    <!-- Current Month Revenue -->
    <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
            <div class="flex-1">
                <p class="text-sm font-medium text-gray-600">Current Month Revenue</p>
                <p class="text-2xl font-bold text-green-600">${{ current_revenue|floatformat:0|intcomma }}</p>
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
                <p class="text-sm font-medium text-gray-600">Annual Revenue ({{ current_year }})</p>
                <p class="text-2xl font-bold text-blue-600">${{ total_annual_revenue|floatformat:0|intcomma }}</p>
                <p class="text-sm text-gray-500">
                    Booked: ${{ annual_booked_revenue|floatformat:0|intcomma }} | 
                    Forecast: ${{ annual_forecast_revenue|floatformat:0|intcomma }}
                </p>
            </div>
            <div class="ml-4">
                <i class="fas fa-chart-line text-blue-500 text-2xl"></i>
            </div>
        </div>
    </div>

    <!-- Monthly Costs -->
    <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
            <div class="flex-1">
                <p class="text-sm font-medium text-gray-600">Monthly Costs</p>
                <p class="text-2xl font-bold text-red-600">${{ current_month_costs|floatformat:0|intcomma }}</p>
                <div class="text-sm text-gray-500">
                    <div>Payroll: ${{ payroll_costs|floatformat:0|intcomma }}</div>
                    <div>Contractors: ${{ contractor_costs|floatformat:0|intcomma }}</div>
                    <div>Other: ${{ other_costs|floatformat:0|intcomma }}</div>
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
                <p class="text-2xl font-bold {% if monthly_profit >= 0 %}text-green-600{% else %}text-red-600{% endif %}">
                    ${{ monthly_profit|floatformat:0|intcomma }}
                </p>
                <p class="text-sm text-gray-500">{{ monthly_profit_margin|floatformat:1 }}% margin</p>
            </div>
            <div class="ml-4">
                <i class="fas fa-chart-pie {% if monthly_profit >= 0 %}text-green-500{% else %}text-red-500{% endif %} text-2xl"></i>
            </div>
        </div>
    </div>
</div>

<!-- Secondary Metrics -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
    <!-- Active Clients -->
    <div class="bg-white rounded-lg shadow p-4">
        <div class="text-center">
            <p class="text-2xl font-bold text-blue-600">{{ total_clients|intcomma }}</p>
            <p class="text-sm text-gray-600">Active Clients</p>
        </div>
    </div>

    <!-- Projects -->
    <div class="bg-white rounded-lg shadow p-4">
        <div class="text-center">
            <p class="text-2xl font-bold text-purple-600">{{ total_projects|intcomma }}</p>
            <p class="text-sm text-gray-600">Total Projects</p>
            <p class="text-xs text-gray-500">{{ booked_projects }} booked | {{ forecast_projects }} forecast</p>
        </div>
    </div>

    <!-- Team Size -->
    <div class="bg-white rounded-lg shadow p-4">
        <div class="text-center">
            <p class="text-2xl font-bold text-orange-600">{{ total_team_members|intcomma }}</p>
            <p class="text-sm text-gray-600">Team Members</p>
        </div>
    </div>

    <!-- Annual Costs -->
    <div class="bg-white rounded-lg shadow p-4">
        <div class="text-center">
            <p class="text-2xl font-bold text-red-600">${{ total_annual_costs|floatformat:0|intcomma }}</p>
            <p class="text-sm text-gray-600">Annual Costs</p>
        </div>
    </div>

    <!-- Annual Profit -->
    <div class="bg-white rounded-lg shadow p-4">
        <div class="text-center">
            <p class="text-2xl font-bold {% if annual_profit >= 0 %}text-green-600{% else %}text-red-600{% endif %}">
                ${{ annual_profit|floatformat:0|intcomma }}
            </p>
            <p class="text-sm text-gray-600">Annual Profit</p>
            <p class="text-xs text-gray-500">{{ annual_profit_margin|floatformat:1 }}% margin</p>
        </div>
    </div>
</div>

<!-- Revenue Chart -->
<div class="bg-white rounded-lg shadow mb-8">
    <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex justify-between items-center">
            <h2 class="text-xl font-semibold text-gray-900">Monthly Revenue</h2>
            <div class="flex space-x-4">
                <select id="yearSelect" class="border border-gray-300 rounded-md px-3 py-2">
                    <option value="2024">2024</option>
                    <option value="2025" selected>2025</option>
                    <option value="2026">2026</option>
                </select>
                <button id="refreshChart" class="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600">
                    <i class="fas fa-refresh mr-2"></i>Refresh
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

    <!-- Cost Management -->
    <div class="bg-white rounded-lg shadow p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Cost Management</h3>
        <div class="space-y-3">
            <a href="/admin/agency/cost/add/" class="block w-full bg-red-500 text-white text-center py-2 px-4 rounded-md hover:bg-red-600">
                <i class="fas fa-plus mr-2"></i>Add Cost
            </a>
            <a href="/admin/agency/cost/?is_contractor__exact=1" class="block w-full bg-orange-500 text-white text-center py-2 px-4 rounded-md hover:bg-orange-600">
                <i class="fas fa-users mr-2"></i>Manage Contractors
            </a>
            <a href="/admin/agency/cost/" class="block w-full bg-gray-500 text-white text-center py-2 px-4 rounded-md hover:bg-gray-600">
                <i class="fas fa-list mr-2"></i>View All Costs
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
</div>
{% endblock %}

{% block extra_js %}
<script>
document.addEventListener('DOMContentLoaded', function() {
    let revenueChart;
    
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
        
        fetch(`{% url 'agency:revenue_chart_data' %}?year=${year}`)
            .then(response => response.json())
            .then(data => {
                revenueChart.data.labels = data.months;
                revenueChart.data.datasets[0].data = data.booked;
                revenueChart.data.datasets[1].data = data.forecast;
                revenueChart.update();
            })
            .catch(error => {
                console.error('Error loading revenue data:', error);
            });
    }
    
    // Event listeners
    document.getElementById('yearSelect').addEventListener('change', loadRevenueData);
    document.getElementById('refreshChart').addEventListener('click', loadRevenueData);
    
    // Initialize
    initializeRevenueChart();
    loadRevenueData();
});
</script>
{% endblock %}
EOF

echo "✅ Created enhanced dashboard template with number formatting"

# 5. UPDATE URLS.PY
echo "📝 Updating URLs..."

cat > agency/urls.py << 'EOF'
# agency/urls.py - Updated URLs
from django.urls import path
from . import views

app_name = 'agency'

urlpatterns = [
    path('', views.dashboard, name='dashboard'),
    path('capacity/', views.capacity_dashboard, name='capacity_dashboard'),
    path('clients/', views.clients_list, name='clients_list'),
    path('clients/<uuid:client_id>/', views.client_detail, name='client_detail'),
    path('projects/', views.projects_list, name='projects_list'),
    path('projects/<uuid:project_id>/', views.project_detail, name='project_detail'),
    path('team/', views.team_list, name='team_list'),
    path('import/', views.import_data, name='import_data'),
    
    # API endpoints
    path('api/revenue-chart/', views.revenue_chart_data, name='revenue_chart_data'),
    path('api/capacity-chart/', views.capacity_chart_data, name='capacity_chart_data'),
    path('api/health/', views.health_check, name='health_check'),
]
EOF

echo "✅ Updated URLs"

# 6. RUN MIGRATIONS
echo "🗄️ Running Django migrations..."

python manage.py makemigrations agency --name unified_cost_and_enhanced_dashboard
python manage.py migrate

echo "✅ Migrations completed"

# 7. COLLECT STATIC FILES
echo "📦 Collecting static files..."
python manage.py collectstatic --noinput 2>/dev/null || echo "  Note: collectstatic skipped (not configured)"

echo ""
echo "🎉 MIGRATION COMPLETED SUCCESSFULLY!"
echo "=================================="
echo ""
echo "📋 WHAT WAS UPDATED:"
echo "  ✅ Unified Cost model (replaces MonthlyCost and RecurringCost)"
echo "  ✅ Added revenue_type filter to Project model (booked/forecast)"
echo "  ✅ Enhanced dashboard with:"
echo "     - Annual revenue breakdown"
echo "     - Monthly cost breakdown (payroll, contractors, other)"
echo "     - Profit calculations with margins"
echo "     - Number formatting with commas"
echo "     - Project type counters"
echo "  ✅ Updated admin interface for new models"
echo "  ✅ Enhanced views with comprehensive metrics"
echo ""
echo "🚀 NEXT STEPS:"
echo "  1. Start your server: python manage.py runserver"
echo "  2. Visit http://127.0.0.1:8000 to see the enhanced dashboard"
echo "  3. Go to /admin to manage the new Cost model"
echo "  4. Import your data: python manage.py import_spreadsheet path/to/file.xlsx G+"
echo ""
echo "📁 BACKUPS CREATED IN: $BACKUP_DIR"
echo ""
echo "🔧 If you need to rollback, your original files are backed up!"
EOF

chmod +x comprehensive_migration_script.sh

echo "✅ Migration script created successfully!"