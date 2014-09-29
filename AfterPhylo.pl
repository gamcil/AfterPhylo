#!/usr/bin/perl

# AfterPhylo (version 0.9.1): a Perl script for manipulating trees after phylogenetic reconstruction
# Copyright (C) 2013-2014, Qiyun Zhu. All rights reserved.
# Licensed under BSD 2-clause license.

use warnings;
use strict;
$| = 1;


## Welcome information ##

print "
Usage:
  perl AfterPhylo.pl [options(s)] [tree(s)]

Input:
  One or more trees in Newick or Nexus format generated by RAxML, PhyML, MrBayes, BEAST or other popular phylogenetics programs.

Options:
  -format=<newick or nexus>: convert tree format to Newick or Nexus.
  -annotate=<annotation table>: annotate trees (append full taxa names to tip labels).
      annotation table format: plain text file with each line like: ID<tab>name.
  -replace: ignore ID instead of appending when annotating (must be used with -annotate).
  -scale=<factor>: scale up/down branch lengths by <factor>.
  -topology: remove branch lengths (keep topology only).
  -unlabeled: remove node labels (confidence values or everything in brackets).
  -confonly: keep confidence values (bootstrap, posterior probability, etc) only from complicated node labels.
  -average: compute average confidence value.
  -collapse=<number>: collapse nodes with confidence value below <number>.
  -simplify: Simplify branch length values to six digits after decimal point.

\n"
and exit 0 if ($#ARGV < 0);


## Global variables ##

my @files;


## Program options ##

my %switches =(
	"annotate" => 0,
	"scale" => 0,
	"deBLength" => 0,
	"deNLabel" => 0,
	"confOnly" => 0,
	"rate" => 0,
	"collapse" => 0,
	"convert" => 0,
	"ignoreID" => 0,
	"shrink" => 0
);


## Read switches ##

for (my $i=0; $i<=$#ARGV; $i++){
	my $s = $ARGV[$i];
	if ($s =~ /^-/){										
		if ($s =~ /^-format=(.+)$/){$switches{"convert"} = lc($1);}
		if ($s =~ /^-annotate=(.+)$/){
			die "Error: Annotation table $1 does not exist.\n" unless -e($1);
			$switches{"annotate"} = $1;
		}
		$switches{"scale"} = $1 if ($s =~ /^-scale=([0-9]*\.?[0-9]+)$/);
		$switches{"collapse"} = $1if ($s =~ /^-collapse=([0-9]*\.?[0-9]+)$/);
		$switches{"deBLength"} = 1 if ($s eq "-topology");
		$switches{"deNLabel"} = 1 if ($s eq "-unlabeled");
		$switches{"confOnly"} = 1 if ($s eq "-confonly");
		$switches{"rate"} = 1 if ($s eq "-average");
		$switches{"shrink"} = 1 if ($s eq "-simplify");
		$switches{"ignoreID"} = 1 if ($s eq "-replace");
	}else{
		die "Error: File $s does not exist.\n" unless -e($s);
		push(@files, $s);
	}
}

foreach my $file (@files){

	## Check tree format ##
	my $format;
	open IN, "<$file";
	$_ = <IN>;
	if (/^#NEXUS/i){
		$format = "nexus";
	}elsif (/^\(/){
		$format = "newick";
	}else{
		print "The format of $file is unrecognizable.\n";
		next;
	}
	close IN;

	## Read tree ##	
	my $tree;
	open IN, "<$file";
	if ($format eq "newick"){
		while (<IN>){
			s/\s+$//;
			next unless $_;
			next if /^#/;
			$tree .= $_;
		}
	}elsif ($format eq "nexus"){
		my %taxa;
		while (<IN>){
			last if /begin trees/i;
		}
		$_ = <IN>;
		while (<IN>){
			last if /;/;
			$_ =~ s/^\s+//;
			my @a = split(/[\s+,]/,$_);
			$a[1] =~ s/['"]//g;
			$taxa{$a[0]} = $a[1];
		}
		while (<IN>){
			last if /^\s*tree/i;
		}
		close IN;
		s/\s+$//;
		$tree = substr($_, index($_, '=')+1);
		$tree =~ s/^\s+\[&.\]\s+(\()/$1/;
		$tree =~ s/^\s+//;
		foreach my $key (keys %taxa){
			$tree =~ s/([(,])($key)([:)\[])/$1$taxa{$key}$3/g; # replace ID with name
		}
	}
	close IN;

	my $save = 1; # whether the result should be saved.

	## Scale up/down branch lengths (-s) ##
	if (my $factor = $switches{"scale"}){
		$tree =~ s/(:)([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)([,)[])/$1.$2*$factor.$4/ge;
	}

	## Remove node labels (-n) ##
	if ($switches{"deNLabel"}){
		$tree =~ s/\[.+?\]//g;
		$tree =~ s/\)[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?([:,\)\[])/\)$2/g;
	}

	## Remove branch lengths (-l) ##
	if ($switches{"deBLength"}){
		$tree =~ s/:[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?([,)[])/$2/g;
	}

	## Shrink branch lengths (-m) ##
	if ($switches{"shrink"}){
		$tree =~ s/:([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)([,)[])/':'.sprintf('%.6f',$1).$3/ge;
	}

	## Keep confidence values only
	if ($switches{"confOnly"}){
		$tree =~ s/\)\[&.*?prob\(percent\)="(\d+?)".*?\]/\)$1/g;
		$tree =~ s/\)\[&.*?posterior=([0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?).*?\]/')'.sprintf('%.f',$1*100)/ge;
		$tree =~ s/\[.+?\]//g;
	}

	## Convert formats
	if (($format eq "nexus") && ($switches{"convert"} eq "newick")){
		$tree =~ s/\[&.*?\]//g;
		$format = "newick";
	}
	if (($format eq "newick") && ($switches{"convert"} eq "nexus")){
		$format = "nexus";
	}
	
	## Compute average confidence value ##
	if ($switches{"rate"}){
		$save = 0;
		my $s = $tree;
		my $nNode;
		my $nScore;
		my $averageScore;
		while ($s =~ s/\)([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)[:,\)]//){
			$nNode ++;
			$nScore	+= $1;
		}
		$averageScore =  sprintf('%.3f', $nScore/$nNode);
		print "$file analyzed.\n";
		print "  Number of nodes: $nNode.\n";
		print "  Total score: $nScore.\n";
		print "  Average score: $averageScore.\n";
	}

	## Collapse unconvincing nodes
	if ($switches{"collapse"}){
		if ($tree =~ /:/){ # branch lengths present
			while ($tree =~ s/(\(([^\(\)]|(?1))*\))([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?):([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)/$1&$3:$5/){
				if ($3 < $switches{"collapse"}){
					my $iBefore = $-[0];
					my $iAfter = $+[0];
					my $parentLength = $5;
					
					my $children = $1;
					
					# This is an advanced trick.
					# I am not quite clear about the syntax,
					# but I thank *ysth* for sharing the code with me.
					# and other people who participated in the discussion.
					# See this post: http://stackoverflow.com/questions/11741636/perl-replace-the-top-level-numbers-onlny-from-a-tree/
					# I made slight modifications to the code and get the one below:
					
					$children =~ s/(?:^\(|(\((?:(?>[^()]*)|(?1))*\)))\K|([0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?):\K([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)/$4?$4+$parentLength:""/ge;
					
					$children = substr($children,1,length($children)-2);
					$tree = substr($tree,0,$iBefore).$children.substr($tree,$iAfter+1);
				}
			}
			$tree =~ s/&//g;
		}else{ # branch lengths absent
			while ($tree =~ s/(\(([^\(\)]|(?1))*\))([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)([,\)])/$1&$3$5/){
				if ($3 < $switches{"collapse"}){
					my $children = substr($1,1,length($1)-2);
					$tree = substr($tree,0,$-[0]).$children.$5.substr($tree,$+[0]+1);
				}
			}
			$tree =~ s/&//g;
		}
	}
	
	## Annotate trees ##
	if ($switches{"annotate"}){
		my %names;
		open NAMES, "<".$switches{"annotate"};
		while (<NAMES>){
			s/\s+$//;
			next unless $_;
			next if /^#/;
			s/\t+$//;
			if (/\t/){
				my @a = split ("\t", $_);
				print "Warning: ID $a[0] is not unique.\n" if $names{$a[0]};
				$names{$a[0]} = $a[0]." ".$a[1];
				$names{$a[0]} = $a[1] if $switches{"ignoreID"};
			}else{ # if taxa name is missing, use ID as name.
				print "Warning: ID $_ is not unique.\n" if $names{$_};
				$names{$_} = $_;
			}
		}
		close NAMES;
		foreach my $key (keys %names){
			if (($format eq "nexus") && ($names{$key} =~ /[.\s]/)){$names{$key} = "'$names{$key}'";}
			$tree =~ s/([(,\]])$key([,:)\[])/$1$names{$key}$2/g;
		}
	}

	## Save result
	next unless $save;
	my $outfile;
	if ($file =~ /(.+)\.([^.]+)$/){
		$outfile = "$1.out.$2";
	}else{
		$outfile = "$file.out";
	}
	open OUT, ">$outfile";
	print OUT "#NEXUS\nBEGIN TREES;\n\tTREE 1 = " if ($format eq "nexus");
	print OUT $tree;
	print OUT "\nEND;\n" if ($format eq "nexus");
	close OUT;
	print "$file was processed and saved as $outfile.\n";
}

exit 0;


