{% set specificTasks = pillar['deviceinfo'].get('specificTasks', []) %}

{% if pillar.get('collect_framework', False) == True %}

collect_framework_directory:
  file.directory:
    - names:
        - /ipaas/collect_framework/bin
        - /ipaas/collect_framework/config
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

collect_framework_conf:
  file.managed:
    - name: /ipaas/collect_framework/config/collect.json
    - source: salt://paitools/files/collect_framework/collect.json
    - user: root
    - group: root
    - mode: 644
    - makedirs: True
    - require:
        - file: collect_framework_directory

collect_framework_bin:
  file.managed:
    - name: /ipaas/collect_framework/bin/collect
    - source: http://salt-source.oss-cn-hangzhou.aliyuncs.com/collect_framework/{{ pillar['collect_framework_version'] }}/collect
    - source_hash: http://salt-source.oss-cn-hangzhou.aliyuncs.com/collect_framework/{{ pillar['collect_framework_version'] }}/collect.md5
    - user: root
    - group: root
    - mode: 755
  - makedirs: True
                - require:
                - file: collect_framework_directory

collect_framework_service:
  file.managed:
    - name: /lib/systemd/system/collect_framework.service
    - source: salt://paitools/files/collect_framework/collect_framework.service
    - user: root
    - group: root
    - mode: 644
    - require:
        - file: collect_framework_bin
  cmd.run:
    - name: systemctl daemon-reload
    - unless: systemctl status collect_framework
  service.running:
    - name: collect_framework
    - enable: true
    - restart: true
    - watch:
        - file: collect_framework_bin

{% endif %}
