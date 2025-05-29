from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import date, timedelta
from decimal import Decimal
import random
from agency.models import Company, MonthlyRevenue, Project, Client, Cost, UserProfile

class Command(BaseCommand):
    help = 'Generate test revenue data across multiple years'

    def add_arguments(self, parser):
        parser.add_argument(
            '--years',
            type=str,
            default='2023,2024,2025',
            help='Comma-separated list of years to generate data for'
        )
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing data before generating'
        )

    def handle(self, *args, **options):
        company = Company.objects.first()
        if not company:
            self.stdout.write(self.style.ERROR('No company found. Please create a company first.'))
            return

        years = [int(y.strip()) for y in options['years'].split(',')]
        
        if options['clear']:
            self.stdout.write('Clearing existing monthly revenue data...')
            MonthlyRevenue.objects.filter(company=company).delete()
            self.stdout.write(self.style.SUCCESS('Cleared existing data'))

        self.stdout.write(f'Generating revenue data for years: {years}')

        for year in years:
            self.generate_year_data(company, year)

        self.stdout.write(self.style.SUCCESS('Successfully generated test revenue data'))

    def generate_year_data(self, company, year):
        """Generate monthly revenue data for a specific year"""
        
        # Base values that grow over time
        base_booked = 150000 + (year - 2023) * 50000
        base_forecast = 50000 + (year - 2023) * 20000
        
        # Seasonal factors (higher in Q2 and Q4)
        seasonal_factors = [
            0.85, 0.90, 0.95,  # Q1
            1.05, 1.10, 1.15,  # Q2
            0.95, 0.90, 0.95,  # Q3
            1.10, 1.15, 1.20   # Q4
        ]
        
        for month in range(1, 13):
            # Calculate revenue with some randomness
            seasonal_factor = seasonal_factors[month - 1]
            
            booked_revenue = Decimal(
                base_booked * seasonal_factor * (0.9 + random.random() * 0.2)
            )
            forecast_revenue = Decimal(
                base_forecast * seasonal_factor * (0.8 + random.random() * 0.4)
            )
            
            # Create or update monthly revenue records
            MonthlyRevenue.objects.update_or_create(
                company=company,
                year=year,
                month=month,
                revenue_type='booked',
                defaults={'revenue': booked_revenue}
            )
            
            MonthlyRevenue.objects.update_or_create(
                company=company,
                year=year,
                month=month,
                revenue_type='forecast',
                defaults={'revenue': forecast_revenue}
            )
            
            self.stdout.write(
                f'  {year}-{month:02d}: '
                f'Booked ${booked_revenue:,.0f}, '
                f'Forecast ${forecast_revenue:,.0f}'
            )
        
        # Also generate some projects for this year
        self.generate_projects(company, year)
        
        # Generate costs if they don't exist
        self.generate_costs(company, year)

    def generate_projects(self, company, year):
        """Generate some test projects for the year"""
        
        # Get or create test clients
        client_names = ['Acme Corp', 'TechStart Inc', 'Global Solutions', 'Digital Ventures']
        clients = []
        
        for name in client_names:
            client, _ = Client.objects.get_or_create(
                company=company,
                name=name,
                defaults={
                    'status': 'active'
                }
            )
            clients.append(client)
        
        # Generate 3-5 projects per quarter
        project_count = 0
        for quarter in range(4):
            num_projects = random.randint(3, 5)
            
            for _ in range(num_projects):
                month = quarter * 3 + random.randint(1, 3)
                start_date = date(year, month, 1)
                
                # Project duration 1-6 months
                duration_months = random.randint(1, 6)
                end_date = start_date + timedelta(days=duration_months * 30)
                
                # Revenue based on duration
                base_monthly = random.randint(30000, 80000)
                total_revenue = Decimal(base_monthly * duration_months)
                total_hours = Decimal(duration_months * 160)  # Approx hours
                
                project_count += 1
                project_name = f"{year} Project {project_count}"
                
                # 70% booked, 30% forecast
                revenue_type = 'booked' if random.random() < 0.7 else 'forecast'
                
                Project.objects.create(
                    company=company,
                    name=project_name,
                    client=random.choice(clients),
                    start_date=start_date,
                    end_date=end_date,
                    total_revenue=total_revenue,
                    total_hours=total_hours,
                    revenue_type=revenue_type,
                    status='active' if end_date >= timezone.now().date() else 'completed'
                )
        
        self.stdout.write(f'  Created {project_count} projects for {year}')

    def generate_costs(self, company, year):
        """Generate operating costs if they don't exist"""
        
        # Check if we already have costs
        existing_costs = Cost.objects.filter(company=company).exists()
        if existing_costs:
            return
        
        # Base costs
        cost_items = [
            ('Office Rent', 'rent', 15000),
            ('Software Licenses', 'software', 5000),
            ('Insurance', 'insurance', 3000),
            ('Marketing', 'marketing', 8000),
            ('Professional Services', 'professional', 4000),
            ('Utilities', 'utilities', 2000),
            ('Equipment', 'office', 3000),
        ]
        
        for name, cost_type, amount in cost_items:
            Cost.objects.create(
                company=company,
                name=name,
                cost_type=cost_type,
                amount=Decimal(amount),
                frequency='monthly',
                start_date=date(2023, 1, 1),
                is_active=True
            )
        
        self.stdout.write(f'  Created {len(cost_items)} cost items')
