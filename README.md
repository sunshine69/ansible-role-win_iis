Role: win_iis
=========

Install IIS and dotnet suites

Requirements
------------


Role Variables
--------------

If not defined anywhere, the for a variable, dict key name will be the exact parameter name of the corresponding ansible modules.

- `win_feature_source` - Path to the source to allow for win_feature to install/remove. Optional - Default not set.

The path points to a directory which seems not obvious. It looks like a signature to allow windows to find out its installation media rather than a directory containing files of sources information.

Example:
```win_feature_source: 'z:\sources\sxs'
```

- `win_iis_base_features` - a list of dict of base features - optional - default
```
win_iis_base_features:
  - name: Net-Framework-Core
  - name: Web-Server
    include_sub_features: yes
    include_management_tools: yes
```
- `win_wcf_features` - These are for the WCF to work - see https://docs.microsoft.com/en-us/dotnet/framework/wcf/whats-wcf - optional - default
```
win_wcf_features:
  - name: NET-HTTP-Activation
  - name: NET-WCF-HTTP-Activation45
```
- `win_extra_features` - Extra features can be added in inventory - optiona, default []
- `win_features` - The final features list we are going to install - optional - default is union of all above.
``` {{ win_iis_base_features + win_wcf_features + win_extra_features }}
```
- `chocolatey_base_pkgs` - optional - default [ 'dotnetcore' ]
- `chocolatey_extra_pkgs` - optional default  []
- `chocolatey_pkgs` - optional - default 
``` "{{ chocolatey_base_pkgs + chocolatey_extra_pkgs }}"
```

Dependencies
------------


Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: username.rolename, x: 42 }

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
