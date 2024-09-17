#! /usr/bin/perl
use strict;
use warnings;

use Data::Dumper;

use lib '.';
use maindialog;

my $mdlg = MainDialog->init();
$mdlg->show;
exit 0;

