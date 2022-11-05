#!/usr/bin/env python3
import os
import yaml
from jinja2 import Environment, FileSystemLoader
out_config_dir = os.environ.get('OUT_CONFIG_DIR', '/tmp')
yml_config_dir = os.environ.get('YML_CONFIG_DIR', '.')

def yml2conf(ymlfile, outputfile):
    config_data = yaml.load(open(ymlfile))
    # Load templates file from templtes folder
    env = Environment(loader = FileSystemLoader('./templates'),   trim_blocks=True, lstrip_blocks=True)
    template = env.get_template('config_tmpl.py')
    config_out= template.render(config_data)
    # Write file in configfile
    outputfile_path="{0}/{1}_config.sh".format(out_config_dir, outputfile)
    with open(outputfile_path, 'w') as f:
        f.write(config_out)



if __name__ == "__main__":
    for filename in os.listdir(yml_config_dir):
        dsplit = os.path.splitext(filename)
        file_basename = dsplit[0]
        file_extension = dsplit[1]
        filepath = os.path.join(yml_config_dir, filename)
        # # checking if it is a file
        if os.path.isfile(filepath) and ( file_extension == '.yml' or file_extension == '.yaml') :
            yml2conf(filepath, file_basename)
