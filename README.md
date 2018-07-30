Role: win_iis
=========

Install IIS and dotnet suites

Also setup a iis websites and applications.

Requirements
------------


Role Variables
--------------

If not defined anywhere, the for a variable, dict key name will be the exact parameter name of the corresponding ansible modules.

- `win_iis_install_base` - Optional - Default is `False`.
  This flag allows us to install the win_iis_base_features and releated
  chocolatey packages. This usually only requires when we build the instance
  AMI or setup the server the first time - or upgrade the packages to the new
  versions etc..

  By setting this to false the role will skip it and focusing on setting up and
  configure the websites and application pool which save a lot of time.

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

- `win_iis_external_modules` - Default see below.
- `win_iis_msi_pkgs` - Default empty list.

  These above are a list of dictionary to specify a msi packages. The external
  module by default contains the iis rewrite modules if
  `win_iis_rewrite_enabled` is set.

  Example:
```
win_iis_msi_pkgs:
  - msi: <msi_file_name - required>
    url: <base_url_without_file_name_above_to_download_the_file - required>
    ignore_errors: <True/False - ignore errors or not default is False. Not required>
```


- ` win_iis_application_pools` - List of application pool name to be created or remove - Optional - default empty
    If in `win_iis_websites` (see below) is provided and in each
    item the key `application_pool` is set then these values will automatically be parsed
    and merge.

- `win_iis_websites` - List of sites to be creeated - Optional - Default empty
   If in `win_iis_webapplications` (see below) is provided and in
   each item the key `site` is set then these values will automatically be parsed and merged.

- `win_iis_webapplications` - List of web app to be created - Optional - Default empty


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
