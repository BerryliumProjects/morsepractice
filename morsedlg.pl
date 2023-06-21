#! /usr/bin/perl
use strict;
use warnings;

use Data::Dumper;

use lib '.';
use maindialog;
use exercisedialog;
use exercise;


my $mdlg = MainDialog->init();
$mdlg->setControlState('normal');
$mdlg->show;
exit 0;

