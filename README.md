# configgin

A simple cli app in ruby to generate configurations using bosh erb templates
but also pulling in consul configuration values where necessary.

Typically bosh-templates use a "context" (some data) to merge with the templates
in order to create the configuration. But because consul is the primary
source of this data you can typically just pass in a dummy-value for the simple
things that are required of the json object.

```bash
# Example of using context instead of input file, piping stdout output to a file.
configgin --data '{"index": 0, "job": {"name": "uaa"}, "properties":{}}' template.yml.erb > output.yml
```

### Controlling input and output

configgin should usually be invoked like so:

```bash
configgin --data '{"index": 0, "job": {"name": "uaa"}, "properties":{}}' \
  --job cloud_controller_ng \
  --role cc \
  --consul http://127.0.0.1:8500 \
  template.yml.erb > output.yml
```

If you don't want to provide json on the command line, you can specify a filename
via the --input parameter instead of --data.

If you don't want to redirect output you can specify an output file using --output.

```bash
# Example of using input and output files with a template.
configgin --input myjsondata.json --output output.yml --job a --role b --consul c template.yml.erb
```
