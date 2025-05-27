# Generated manually for Cost model

from django.db import migrations, models
import django.db.models.deletion
import uuid

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0004_add_revenue_type_to_project'),
    ]

    operations = [
        migrations.CreateModel(
            name='Cost',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=200)),
                ('cost_type', models.CharField(choices=[('contractor', 'Contractor'), ('payroll', 'Payroll'), ('rent', 'Rent'), ('utilities', 'Utilities'), ('software', 'Software/Technology'), ('office', 'Office Supplies'), ('marketing', 'Marketing'), ('travel', 'Travel'), ('professional', 'Professional Services'), ('insurance', 'Insurance'), ('other', 'Other')], max_length=20)),
                ('description', models.TextField(blank=True)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('frequency', models.CharField(choices=[('monthly', 'Monthly Recurring'), ('one_time', 'One Time'), ('project_duration', 'Spread Over Project Duration')], default='monthly', max_length=20)),
                ('start_date', models.DateField()),
                ('end_date', models.DateField(blank=True, null=True)),
                ('is_contractor', models.BooleanField(default=False)),
                ('vendor', models.CharField(blank=True, max_length=200)),
                ('is_billable', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('company', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.company')),
                ('project', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.project')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['company', 'start_date'], name='agency_cost_company_start_idx'),
                    models.Index(fields=['cost_type', 'is_contractor'], name='agency_cost_type_contractor_idx'),
                ],
            },
        ),
    ]
