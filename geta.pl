#!/usr/bin/perl

$VERSION=0.1;


use Net::DNS;
use MIME::Base32 qw ( RFC );
use MIME::Base64;
use Time::HiRes qw (usleep gettimeofday tv_interval);
use Getopt::Long;
use threads;
use Thread::Queue;

my %opts;

$opts{output}= "STDOUT";
GetOptions(
    "mode=s"   =>   \$opts{mode},
    "output=s" =>   \$opts{output},
    "resolver=s"=>  \$opts{resolver},
    "verbose"  =>   \$opts{verbose},
    "id=s"     =>   \$opts{id},
    "norecurse"=>   \$opts{norecurse},
    "persistent"=>  \$opts{persistent}
);
$opts{mode} = uc $opts{mode};
chomp $opts{id};

if(!length($opts{output})){
   my $fname=$opts{output};
   open($opts{output}, "$fname");
   undef $fname;
}
binmode $opts{output};

if($ARGV[0]) {$opts{target} = $ARGV[0];}

if(!length($opts{mode}) || !length($opts{target})){
   print STDERR << "EOD";
geta $VERSION:      DNS File/Stream Receiver
Component of:  OzymanDNS          Dan Kaminsky(dan\@doxpara.com)
       Usage:  geta [-o file] [-i stream_id] -r [resolver] -m MODE TARGET
     Options:  -m [mode]       :  Transfer Mode *
               -o [output]     :  Output File (stdout)
               -r              :  Nameserver(s) to use
               --id            :  Stream Identifier
               --norecurse     :  Don't recurse queries (use to verify caching)
               --persistent    :  Use a persistent UDP socket   (can be faster)
       Modes:  bit_recurse     :  Data Bitmasked in Precached A Records ( 1b/p)
               b32_cname       :  Data Base32'd as CNAMEs             (~110B/p) 
               b64_txt         :  Data Base64'd in TXT records        (~220B/p)
               b64_txt_stream  :  Same as above, but w/ a live stream (~220B/p)               
EOD
   exit(1);
}

sub bit_recurse{
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{output};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->recurse(0);
    $res->retry(5);
    $res->retrans(1);
    if($opts{persistent}) {$res->persistent_udp(1);}
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;
    
    my $data="";
    my $size=0;
    my @array = ();
    my $sum = 0;
    my $bitsum = 0;
        
    my $bit_id=0;
    while(1)
    {
        if("$bitsum"==0){
           my $reply = $res->query("$sum\-more\-$id.$target", "A");
           if (!($reply && $reply->header->ancount)) {exit(0);}
        }
     
        $bit_id=($sum*8) + $bitsum;
        my $nsid = $bit_id % ($#ns+1);
        $res->nameserver($ns[$nsid]);
        my $addr = "$sum\-$bitsum\-$id.$target";
        $reply = $res->query("$addr", "A");
        if ($reply) {
            my $header = $reply->header;
            if($header->ancount) { $array[$bitsum] = 1; }
            else                 { $array[$bitsum] = 0; }
        }     
        else          { $array[$bitsum] = 0 }
        #if ($array[$bitsum]) {print "$addr: $bitsum = $array[$bitsum]\n";}
        
        if ("$bitsum" == 7)
        {
        	$data = join("", @array);
        	$data = pack("B8", $data);
        	syswrite($file, $data, 1);
         	$bitsum = 0;
            $sum++;
        	$#array = ();
       	}
    
        $bitsum++;
    }
}


sub b32_cname{
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{output};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->retry(5);
    $res->retrans(1);
    if($opts{persistent}) {$res->persistent_udp(1);}
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;

    my $try;
    my $rr;
    my $sum=0;
    my $size=0;
    my $data="";
    my @array;
    my $string;
    my $reply;
    
    while(1)
    {
    	my $query;
    	if(length($id)) { $query = "$sum.$id.get.$target"; }
    	else            { $query = "$sum.get.$target"; };
         	
        my $reply = $res->query("$query", "A");
    	if($reply) {
    	   $try=0;
    	   foreach $rr (grep { $_->type eq 'CNAME' } $reply->answer) {
    	      $data = $rr->cname;
    	      $data =~ s/8/\n/g;
    	      $data =~ s/9/\=/g;
    	      @array = split(/\./, $data);
    	      if($array[0] eq "0") {print STDERR "file complete"; exit(0);}
     	      my $tmp = $#array - 4 - 2;
    	      $string = uc join("", @array[0..$tmp]);
    	      $string = MIME::Base32::decode($string);
    	      $size = length($string);
    	      if($size==0) { print STDERR "bye\n"; exit 0; }
    	      syswrite(STDOUT, $string, length($string));
    	   }
    	} else {
    	   usleep(100*1000);
    	   $try++;
    	   if($try==3) {print STDERR "meh\n";exit(1);}
    	}
    	$sum+=$size;
    }
}

sub b64_txt{
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{output};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my $norecurse = $opts{norecurse};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->retry(5);
    $res->retrans(1);
    if($norecurse) { $res->recurse(0); }
    if($opts{persistent}) {$res->persistent_udp(1);}
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;
    my $status = 1;
    my $offset = 0;
    my $sum;
    
    binmode(STDOUT);
    
    while ($status){
    
    	my $length, $addr;
    	if(length($id)){ $addr= ("$offset-$id.$target"); }
    	else           { $addr= ("$offset.$target"); }
    	my $query = $res->query("$addr", "TXT");
    
    	if ($query) {
    	    foreach $rr (grep { $_->type eq 'TXT' } $query->answer) {
    
    		my @txt = $rr->char_str_list();
    		foreach $textdata (@txt) {
    			$textdata = decode_base64($textdata);
    			print $textdata;
    			$sum += length($textdata);
    			printf(stderr "%s\r", $sum);
    
    			$offset = $offset + length($textdata);
    			$status = length($textdata);
    		}
    	    }
    	    usleep(100*1000);
    	}
    	else {
    	    @reslist=$res->nameservers;
    	    $broken=shift @reslist;
    	    push @reslist, $broken;
    	    $res->nameservers(@reslist);
    	}
    }

}

sub b64_txt_stream {
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{output};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->retry(5);
    $res->retrans(1);
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;
    
    my $status = 1;
    my $offset = 0;
    my $sum;
    my $latest=0;
    
    binmode($file);
    
    my $query=$res->query("latest.$target", "CNAME");
    if($query) {
       foreach $rr (grep { $_->type eq 'CNAME'} $query->answer) {
    	my @namelist = split(/\./, $rr->cname);
    	$latest = int ($namelist[0]);
       }
    }
    
    $offset = $latest - 55*4*8;
    
    my $slackspace = 0;
    my $extratime=0;
    
    while ($status){
    	my $sleepytime = 0;
    
    	my $length;
    	my $mod_size = $offset % (55*2*80);
    	my $addr= ("$mod_size.$target");
    	my @then = gettimeofday();
    	my $reply = $res->query($addr, "TXT");
    	my $temp;
    
    	if ($reply) {
    	    foreach $rr (grep { $_->type eq 'TXT' } $reply->answer) {
        		my @txt = $rr->char_str_list();
        		my $textdata;
        		foreach $textdata (@txt) {
        			$textdata = decode_base64($textdata);
        			if(!$slackspace){ syswrite(STDOUT, $textdata, length($textdata));}
        			else {$temp = $temp . $textdata;}
        			$sum += length($textdata);
        
        			$offset = $offset + length($textdata);
        			$status = length($textdata);
               }
    	    }
    	}
    	else {
    	    #warn "query failed: ", $res->errorstring, "\n";
    	    #$status = 0;
    	    @reslist=$res->nameservers;
    	    $broken=shift @reslist;
    	    push @reslist, $broken;
    	    $res->nameservers(@reslist);
    	}
    	#print scalar tv_interval($then, [gettimeofday]);
    	my @now = gettimeofday();
    
    	my $diffsec = $now[0] - $then[0];
    	my $diffusec= $now[1] - $then[1];
    
    	my $querytime = $diffsec * 1000 * 1000 + $diffusec;
    	my $sleepytime = (880 * 1000) - $querytime - $extratime;
    
    	if ($sleepytime < 0) {
    	    $extratime = abs($sleepytime);
    	    $sleepytime= 0;
    	} else {
    	    $extratime = 0;
    	}
    
    	if($slackspace == 1) {syswrite($file, $temp, length($temp));}
    	if(!$slackspace) {usleep($sleepytime);}
    	else {$slackspace--;}
    
    	printf(stderr "%s\t%s %s %s %s %s\n", $sleepytime, $querytime, $extratime, "$mod_size.$target", ($res->nameservers)[0], $sum);
    }
}

if($opts{mode} eq "B64_TXT")     {b64_txt()};
if($opts{mode} eq "B64_TXT_STREAM")     {b64_txt_stream()};
if($opts{mode} eq "B32_CNAME")   {b32_cname()};
if($opts{mode} eq "BIT_RECURSE") {bit_recurse()};

