# config_gen

A simple cli app in ruby to generate configurations using bosh erb templates
but also pulling in kato configuration values where necessary.

Typically bosh-templates use a "context" (some data) to merge with the templates
in order to create the configuration. But because Kato config is the primary
source of this data you can typically just pass in an empty json object with
properties which also can be empty:

```bash
# Example of using context instead of input file, piping stdout output to a file.
config-gen --context '{"properties":{}}' template.yml.erb > output.yml
```

### Mapping

Bosh templates have certain values in them which may map to different or
non-existent configuration values inside Kato. For this there is the
[config/mappings.yml](config/mappings.yml) file. There is also a section in there
called static_values, these are always present with the dummy value in the file
because we have no corresponding key in Kato config for these.

### Controlling input and output

Config gen has two inputs:

* ERB Template file
* "Context", which is data use for the template rendering. (JSON Formatted)

By default json data is read from stdin to use for population and
outputs to stdout. This can be adjusted using --input and --output for filenames.
--context can be provided instead of --input if you'd like to simply pass in
something via command line argument.

```bash
# Example of using input and output files with a template.
config-gen --input myjsondata.json --output output.yml template.yml.erb
```
