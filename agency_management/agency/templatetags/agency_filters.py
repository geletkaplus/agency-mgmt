from django import template
from django.contrib.humanize.templatetags.humanize import intcomma

register = template.Library()

@register.filter
def currency(value):
    """Format value as currency with commas"""
    try:
        return f"${intcomma(int(float(value)))}"
    except (ValueError, TypeError):
        return "$0"

@register.filter
def currency_decimal(value):
    """Format value as currency with commas and decimals"""
    try:
        return f"${intcomma(round(float(value), 2))}"
    except (ValueError, TypeError):
        return "$0.00"

@register.filter
def number_comma(value):
    """Format number with commas"""
    try:
        return intcomma(int(float(value)))
    except (ValueError, TypeError):
        return "0"
