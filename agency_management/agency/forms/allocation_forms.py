from django import forms
from django.forms import BaseInlineFormSet
from agency.models import ProjectAllocation, UserProfile
from datetime import date
from dateutil.relativedelta import relativedelta
from decimal import Decimal


class ProjectAllocationFormSet(BaseInlineFormSet):
    """Custom formset that creates a grid of allocations by month"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        
        if self.instance and hasattr(self.instance, 'start_date') and hasattr(self.instance, 'end_date'):
            # Get project date range
            self.project_months = self._get_project_months()
            
            # Get all team members for the company
            self.team_members = UserProfile.objects.filter(
                company=self.instance.company,
                status__in=['full_time', 'part_time', 'contractor']
            ).select_related('user').order_by('user__last_name', 'user__first_name')
            
            # Pre-populate forms data
            self._prepare_initial_data()
    
    def _get_project_months(self):
        """Get list of (year, month) tuples for project duration"""
        months = []
        current = self.instance.start_date.replace(day=1)
        end = self.instance.end_date.replace(day=1)
        
        while current <= end:
            months.append((current.year, current.month))
            current += relativedelta(months=1)
        
        return months
    
    def _prepare_initial_data(self):
        """Prepare initial data for the grid"""
        # Get existing allocations
        existing_allocations = {}
        for allocation in self.queryset:
            key = (allocation.user_profile_id, allocation.year, allocation.month)
            existing_allocations[key] = allocation
        
        # Create forms for each team member
        forms_data = []
        for member in self.team_members:
            member_data = {'user_profile': member.id}
            
            # Add allocation for each month
            for year, month in self.project_months:
                key = (member.id, year, month)
                if key in existing_allocations:
                    allocation = existing_allocations[key]
                    member_data[f'hours_{year}_{month}'] = allocation.allocated_hours
                    member_data[f'id_{year}_{month}'] = allocation.id
                else:
                    # Calculate default hours based on project hours
                    default_hours = self._calculate_default_hours(member)
                    member_data[f'hours_{year}_{month}'] = default_hours
            
            forms_data.append(member_data)
        
        self.initial = forms_data
    
    def _calculate_default_hours(self, member):
        """Calculate default hours for a team member"""
        if not self.instance.total_hours:
            return Decimal('0')
        
        # Simple default: divide total hours by number of months and team members
        num_months = len(self.project_months)
        num_members = self.team_members.count()
        
        if num_months > 0 and num_members > 0:
            return self.instance.total_hours / (num_months * num_members)
        
        return Decimal('0')


class ProjectAllocationForm(forms.ModelForm):
    """Custom form for project allocations"""
    
    class Meta:
        model = ProjectAllocation
        fields = ['user_profile', 'year', 'month', 'allocated_hours', 'hourly_rate']
        widgets = {
            'allocated_hours': forms.NumberInput(attrs={
                'class': 'form-control',
                'step': '0.5',
                'min': '0',
                'style': 'width: 60px;'
            })
        }
