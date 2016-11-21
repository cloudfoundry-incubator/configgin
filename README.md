# configgin

A simple cli app in Ruby to generate configurations using [BOSH](https://bosh.io) ERB templates and
a BOSH spec, but also using configurations based on environment variables,
processed using a set of templates.

## Usage

```
Usage: configgin [options]
    -j, --jobs file                  Job configuration JSON
    -e, --env2conf file              Environment to configuration templates YAML
```

## Examples

### Example BOSH spec (bosh_spec.json)
```json
{
    "job": {
        "name": "mysql",
        "templates": [
            {
                "name": "mysql"
            },
            {
                "name": "consul_agent"
            }
        ]
    },
    "networks": {
        "default": {}
    },
    "properties": {
        "acceptance_tests": {
            "include_services": false,
            "include_sso": false,
            "nodes": 2
        }
    }
}  
```

### Example job configuration file (job_config.json)
```json
{
  "job_name": {
    "base": "/tmp/bosh_spec.json",
    "files": {
      "/tmp/my_template.erb": "/tmp/output_file"
    }
  }
}
```

### Example environment variable template file (env2.conf.yml)
```yaml
---
properties.acceptance_tests.nodes: "((TEST_NODE_COUNT))"
properties.uaa.scim.users: "'((TEST_VAR))'"
```

### Example template (my_template.erb)
```erb
Hello, this is the users property: <%= p("uaa.scim.users") %>
```

### Example of using the tool
```bash
TEST_VAR=foo
configgin \
  -e ~/tmp/env2.conf.yml \
  -j ~/tmp/job_config.json
```
