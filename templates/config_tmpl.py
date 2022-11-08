# uid={{ global.uid|default('mcloud') }}
# timeout={{ global.timeout|default('3') }}
# keepLogLines={{ global.keeploglines|default('300') }}
# request_tracing=false

{% for key, value in global.items() %}
{{ key }}={{ value }}
{% endfor %}


declare -A NOTIFICATIONS=(
{% for item in notifications %}
{% if item.type == 'slack' %}
  [{{ item.id }}]="slack|{{ item.token }}|{{ item.channel }}|{% for mentions in item.mentions %}{{ mentions }}{% if not loop.last %} {% endif %}{% endfor %}"
{% elif item.type == 'telegram' %}
  [{{ item.id }}]="telegram|{{ item.bottoken }}|{{ item.groupid }}|{% for mentions in item.mentions %}{{ mentions }}{% if not loop.last %} {% endif %}{% endfor %}"
{% elif item.type == 'sendgrid' %}
  [{{ item.id }}]="sendgrid|{{ item.token }}|{{ item.sender }}|{% for email in item.email|default('[]') %}{{ email }}{% if not loop.last %} {% endif %}{% endfor %}"
{% endif %}
{% endfor %}
)

declare -A CERTS=(
{% for item in certificate %}
  [{{ item.id }}]="{% for nid in item.notification %}{{ nid }}{% if not loop.last %} {% endif %}{% endfor %}|{{ item.reminder | default('50') }}|{% for host in item.domains %}{{ host }}{% if not loop.last %} {% endif %}{% endfor %}|{% for email in item.email|default('[]') %}{{ email }}{% if not loop.last %} {% endif %}{% endfor %}"
{% endfor %}
)

declare -A PROBES=(
{% for p in probes %}
  [{{ p.id }}-{{ loop.index }}]="{{ p.publish | default('false') }}|{{ p.timeout | default('5') }}|{% for nid in p.notification %}{{ nid }}{% if not loop.last %} {% endif %}{% endfor %}|{{ p.repeate_interval | default('180') }}|{% for url in p.urls %}{{ url }}{% if not loop.last %} {% endif %}{% endfor %}|{% for email in p.email|default('[]') %}{{ email }}{% if not loop.last %} {% endif %}{% endfor %}"
{% endfor %}
)
