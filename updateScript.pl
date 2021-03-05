#!/usr/bin/perl

use File::Basename;
use POSIX qw(strftime);
use strict;

my @filenames = ( "52_I2C_EZOPH.pm","52_I2C_EZOORP.pm","52_I2C_EZOPRS.pm");

my $prefix = "FHEM";
my $filename = "";
foreach $filename (@filenames)
{
  my @statOutput = stat($prefix."/".$filename);

  if (scalar @statOutput != 13)
  {
    printf("error: stat has unexpected return value for ".$prefix."/".$filename."\n");
    next;
  }

  my $mtime = $statOutput[9];
  my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
  my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
  my $filetime = $date."_".$time;

  my $filesize = $statOutput[7];


  open (DATEI, ">controls_ezoDevices.txt") or die $!;
  print DATEI ("UPD ".$filetime." ".$filesize." ".$prefix."/".$filename."\n");
  close (DATEI);
  printf("UPD ".$filetime." ".$filesize." ".$prefix."/".$filename."\n");
}
