# Generated migration for adding revenue_type to Project

from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0003_contractorexpense_expense_monthlycost_recurringcost_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='revenue_type',
            field=models.CharField(
                choices=[('booked', 'Booked'), ('forecast', 'Forecast')],
                default='booked',
                max_length=10
            ),
        ),
    ]
