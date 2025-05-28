# agency/models.py - Migration-safe version
from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MinValueValidator, MaxValueValidator
from decimal import Decimal
import uuid

class Company(models.Model):
    """Company entity - supports multi-company setup"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=10, unique=True)
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
    is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")
    
    
    def __str__(self):
        return f"{self.user.get_full_name()} ({self.role})"
    
    @property
    def monthly_capacity_hours(self):
        return (self.weekly_capacity_hours * Decimal('4.33'))
    
    @property
    def monthly_salary_cost(self):
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
    """Projects for clients"""
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
    
    start_date = models.DateField()
    end_date = models.DateField()
    
    total_revenue = models.DecimalField(max_digits=12, decimal_places=2)
    total_hours = models.DecimalField(max_digits=8, decimal_places=1)
    project_type = models.CharField(max_length=20, choices=TYPE_CHOICES, default='project')
    revenue_type = models.CharField(max_length=10, choices=REVENUE_TYPE_CHOICES, default='booked')
    
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='planning')
    project_manager = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                                      related_name='managed_projects')
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    team_members = models.ManyToManyField(
        'UserProfile',
        related_name='assigned_projects',
        blank=True,
        help_text='Team members assigned to this project'
    )

    def __str__(self):
        return f"{self.client.name} - {self.name}"

class ProjectAllocation(models.Model):
    """Monthly allocation of users to projects"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='allocations')
    user_profile = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='project_allocations')
    
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    allocated_hours = models.DecimalField(max_digits=6, decimal_places=1, 
                                        validators=[MinValueValidator(Decimal('0.1'))])
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
        return self.allocated_hours * self.hourly_rate

class MonthlyRevenue(models.Model):
    """Monthly revenue tracking"""
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
    """Unified cost model - NEW"""
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
    
    name = models.CharField(max_length=200)
    cost_type = models.CharField(max_length=20, choices=COST_TYPE_CHOICES)
    description = models.TextField(blank=True)
    
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    frequency = models.CharField(max_length=20, choices=FREQUENCY_CHOICES, default='monthly')
    
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    
    is_contractor = models.BooleanField(default=False)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='costs', 
                               null=True, blank=True)
    
    vendor = models.CharField(max_length=200, blank=True)
    is_billable = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        indexes = [
            models.Index(fields=['company', 'start_date']),
            models.Index(fields=['cost_type', 'is_contractor']),
        ]
    
    def __str__(self):
        return f"{self.name} - ${self.amount}"
    
    @property
    def monthly_amount(self):
        if self.frequency == 'monthly':
            return self.amount
        elif self.frequency == 'project_duration' and self.start_date and self.end_date:
            months = (self.end_date.year - self.start_date.year) * 12 + (self.end_date.month - self.start_date.month) + 1
            return self.amount / months if months > 0 else self.amount
        return self.amount

class CapacitySnapshot(models.Model):
    """Monthly capacity snapshots"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    company = models.ForeignKey(Company, on_delete=models.CASCADE, related_name='capacity_snapshots')
    year = models.IntegerField()
    month = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])
    
    total_capacity_hours = models.DecimalField(max_digits=8, decimal_places=1)
    total_allocated_hours = models.DecimalField(max_digits=8, decimal_places=1)
    total_revenue = models.DecimalField(max_digits=12, decimal_places=2)
    utilization_rate = models.DecimalField(max_digits=5, decimal_places=2)
    
    role_capacity_data = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        unique_together = ['company', 'year', 'month']
        indexes = [
            models.Index(fields=['company', 'year', 'month']),
        ]
    
    def __str__(self):
        return f"{self.company.name} Capacity ({self.year}/{self.month:02d}) - {self.utilization_rate}%"

# Keep legacy models for compatibility during migration
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
