# Generated migration to add billable_rate to Project model

from django.db import migrations, models
from decimal import Decimal

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0005_cost'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='billable_rate',
            field=models.DecimalField(
                max_digits=8, 
                decimal_places=2, 
                default=Decimal('150.00'),
                help_text='Default billable rate per hour for this project'
            ),
        ),
        migrations.AddField(
            model_name='project',
            name='calculated_hours',
            field=models.DecimalField(
                max_digits=10, 
                decimal_places=2, 
                null=True,
                blank=True,
                help_text='Calculated hours based on total revenue / billable rate'
            ),
        ),
        migrations.AddField(
            model_name='projectallocation',
            name='billable_rate_override',
            field=models.DecimalField(
                max_digits=8, 
                decimal_places=2, 
                null=True,
                blank=True,
                help_text='Override billable rate for this specific allocation'
            ),
        ),
        migrations.AddField(
            model_name='projectallocation',
            name='notes',
            field=models.TextField(
                blank=True,
                help_text='Notes about this allocation'
            ),
        ),
    ]
