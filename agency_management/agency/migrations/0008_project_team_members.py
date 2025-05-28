from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('agency', '0007_auto_allocation_improvements'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='team_members',
            field=models.ManyToManyField(
                to='agency.UserProfile',
                related_name='assigned_projects',
                blank=True,
                help_text='Team members assigned to this project'
            ),
        ),
    ]
