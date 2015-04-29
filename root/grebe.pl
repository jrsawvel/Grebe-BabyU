#!/usr/bin/perl -wT
use strict;
$|++;
use lib '../lib';
use lib '../lib/CPAN';

use Client::Dispatch;
Client::Dispatch::execute();

