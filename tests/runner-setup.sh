#!/bin/bash

DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
export PATH=$DIR/../tests:$PATH
export PERL5LIB=$DIR/atlasprod/perl_modules:$PERL5LIB

echo $PERL5LIB