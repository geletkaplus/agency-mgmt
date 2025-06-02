from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('agency', '0012_projectallocation_is_pm'),
    ]

    operations = [
        migrations.AddField(
            model_name='projectallocation',
            name='week',
            field=models.IntegerField(null=True, blank=True, help_text='Week number for weekly allocations'),
        ),
        migrations.AlterField(
            model_name='projectallocation',
            name='allocated_hours',
            field=models.DecimalField(max_digits=6, decimal_places=1, help_text='Hours allocated for this period'),
        ),
        migrations.AlterUniqueTogether(
            name='projectallocation',
            unique_together={('project', 'user_profile', 'year', 'month', 'week')},
        ),
    ]
