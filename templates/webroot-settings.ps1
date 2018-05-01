$env:Path = "$Env:systemroot\system32\inetsrv\"

{% for key in win_iis_webroot.keys() %}
  appcmd.exe set config /commit:WEBROOT /section:globalization /{{ key }}:{{ win_iis_webroot[key] }}
{% endfor %}
