from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('agency', '0011_alter_monthlycost_unique_together_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='projectallocation',
            name='is_project_manager',
            field=models.BooleanField(default=False, help_text='Is this person the PM for this project?'),
        ),
    ]
