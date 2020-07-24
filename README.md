[![Anaconda-Server Badge](https://anaconda.org/ebi-gene-expression-group/perl-atlas-modules/badges/installer/conda.svg)](https://conda.anaconda.org/ebi-gene-expression-group)

# Atlas in house perl modules

Repository includes internal perl modules that is used for processing studies in atlas data production pipeline particularly handling MAGE-TABs, baseline and differential analysis, zooma mappings, release data exports. 

# Changing config files for local setup

Execution of certain scripts when using the conda installation might fail because certain configuration files won't be found. Currently the main work-around for this (sorry, yes, this is a work-around) is to replace the AtlasSiteConfig.yaml and ArrayExpressSiteConfig.yaml for files that point to the necessary content in the machine where this runs. For this, follow these steps (which assume that a conda environment with perl-atlas-modules is installed):

1.- Find the path to your conda env that contains perl-atlas-modules:

```
PERL_ATLAS_ENV=$(conda env list | grep perl-atlas | awk '{ print $2 }')
echo $PERL_ATLAS_ENV
```

2.- Copy the AtlasSite and ArrayExpressSite config files to a safe editable location

```
mkdir ~/atlas-config
cp $PERL_ATLAS_ENV/atlasprod/supporting_files/ArrayExpressSiteConfig.yml ~/atlas-config/
cp $PERL_ATLAS_ENV/atlasprod/supporting_files/AtlasSiteConfig.yml ~/atlas-config/
```

3.- Replace contents on `atlasprod/supporting_files/` with links to the copied files

```
cd $PERL_ATLAS_ENV/atlasprod/supporting_files
rm ArrayExpressSiteConfig.yml && ln -s ~/atlas-config/ArrayExpressSiteConfig.yml ArrayExpressSiteConfig.yml
rm AtlasSiteConfig.yml && ln -s ~/atlas-config/AtlasSiteConfig.yml AtlasSiteConfig.yml
```

4.- Edit files in `~/atlas-config/` to reflect local setup.

These links (step 3) will be deleted if the conda package is re-installed in the same environment. We will provide a better way of dealing with this soon.


