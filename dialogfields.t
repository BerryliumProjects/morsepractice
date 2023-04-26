#! /usr/bin/perl

use lib '.';
use Tk;
use Test::Simple tests=>2;
use dialogfields;
use Data::Dumper;

use Tk::ROText;
use Tk::DialogBox;

use Tk::After;


# print Dumper \$d1;

my $w = MainWindow->new();
ok(defined $w, 'Empty window created');
$w->fontCreate('msgbox',-family=>'helvetica', -size=>-14);
my $callback = sub {1;};
my $df = DialogFields->init($w,$callback,300);
my $e = $df->entries; # gridframe control values
ok(defined $df, 'Empty dialogfields created');

$df->addEntryField('Entry Field', 'entry', 40, 'contents');
$df->addCheckbuttonField('Checkbutton Left', 'cbleft',  1);
$df->addCheckbuttonField2('Checkbutton Right', 'cbright', 0);
$tf1 = $df->addWideTextField(undef, 'widetext', 10, 75, '');
$tf1->insert('end', 'Wide text field contents');
$lb1 = $df->addListboxField('Listbox', 'listbox', 40);
$lb1->insert('end', 'Option1');
$lb1->insert('end', 'Option 2');
$df->addButtonField('Quit', 'quit',  'q', sub{$w->destroy});



$w->MainLoop();
print Dumper $e;
