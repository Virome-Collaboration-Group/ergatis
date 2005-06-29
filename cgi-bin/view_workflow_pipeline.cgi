#!/local/perl/bin/perl -w

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Date::Manip;
use File::stat;
use POSIX;
use XML::Twig;

my $q = new CGI;

print $q->header( -type => 'text/html' );

my $xml_input = $q->param("instance") || die "pass instance";

print_header();

if (-f $xml_input) {
    parseXMLFile($xml_input);
} else {
    die "don't know what to do with $xml_input";
}

print_footer();

exit(0);

sub parseXMLFile {
    my $file = shift;
    my $twig = new XML::Twig;

    $twig->parsefile($file);
   
    my $commandSetRoot = $twig->root;
    my $commandSet = $commandSetRoot->first_child('commandSet');
    
    ## pull desired info out of the root commmandSet
    ## pull: project space usage
    my ($starttime, $endtime, $lastmodtime, $state, $runtime) = ('n/a', 'n/a', '', 'unknown', 'n/a');
    my ($starttimeobj, $endtimeobj);
    
    if ($commandSet->first_child('startTime') ) {
        $starttimeobj = ParseDate($commandSet->first_child('startTime')->text());
        $starttime = UnixDate($starttimeobj, "%c");
    }

    if ($commandSet->first_child('endTime') ) {
        $endtimeobj = ParseDate($commandSet->first_child('endTime')->text());
        $endtime = UnixDate($endtimeobj, "%c");
    }

    if ( $commandSet->first_child('state') ) {
        $state  = $commandSet->first_child('state')->text();
    }

    ## we can calculate runtime only if start and end time are known, or if start is known and state is running
    if ($starttimeobj) {
        if ($endtimeobj) {
            $runtime = strftime( "%H hr %M min %S sec", reverse split(/:/, DateCalc($starttimeobj, $endtimeobj)) );
        } elsif ($state eq 'running') {
            $runtime = strftime( "%H hr %M min %S sec", reverse split(/:/, DateCalc("now", $starttimeobj)) ) . ' ...';
        }
    }

    my $filestat = stat($file);
    my $user = getpwuid($filestat->uid);
    $lastmodtime = time - $filestat->mtime;
    $lastmodtime = strftime( "%H hr %M min %S sec", reverse split(/:/, DateCalc("today", ParseDate(DateCalc("now", "- ${lastmodtime} seconds")) ) ));

    ## quota information (only works if in /usr/local/annotation/SOMETHING)
    my $quotastring = '';
    if ($file =~ m|^(/usr/local/annotation/.+?/)|) {
        $quotastring = `getquota -N $1`;
        if ($quotastring =~ /(\d+)\s+(\d+)/) {
            my ($limit, $used) = ($1, $2);
            $quotastring = sprintf("%.1f", ($used/$limit) * 100) . "\% ($used KB of $limit KB used)";
        } else {
            $quotastring = 'error parsing quota information';
        }
    } else {
        $quotastring = 'unavailable (outside of project area)';
    }

    print "<div id='pipelinesummary'>\n";
    print "    <div id='pipeline'>$file</div>\n";
    print "    <div class='pipelinestat' id='pipelinestart'><strong>start:</strong> $starttime</div>\n";
    print "    <div class='pipelinestat' id='pipelineend'><strong>end:</strong> $endtime</div>\n";
    print "    <div class='pipelinestat' id='pipelinelastmod'><strong>last mod:</strong> $lastmodtime</div><br>\n";
    print "    <div class='pipelinestat' id='pipelinestate'><strong>state:</strong> $state</div>\n";
    print "    <div class='pipelinestat' id='pipelineuser'><strong>user:</strong> $user</div>\n";
    print "    <div class='pipelinestat' id='pipelineruntime'><strong>runtime:</strong> $runtime</div><br>\n";
    print "    <div class='pipelinestat' id='projectquota'><strong>quota:</strong> $quotastring</div>\n";
    print "    <div class='timer' id='pipeline_timer_label'>update in <span id='pipeline_counter'>10</span>s</div>\n";
    print "    <div id='pipelinecommands'>" .
                   "[<a href='/tigr-scripts/papyrus/cgi-bin/run_wf.cgi?instancexml=$file'>rerun</a>] " .
                   "[<a href='/tigr-scripts/papyrus/cgi-bin/kill_wf.cgi?instancexml=$file'>kill</a>] " .
                   "[<a href='http://htcmaster.tigr.org/antware/condor-status/index.cgi' target='_blank'>condor status</a>]" .
              "</div>\n";
    print "</div>\n";
    print "<script>pipelineCountdown();</script>";
    
    ## parse the root commandSet to find components and set definitions
    parseCommandSet( $commandSet );
}


sub parseCommandSet {
    my ($commandSet) = @_;
   
    my $configMapId = $commandSet->first_child('configMapId')->text();
    my $type = $commandSet->{att}->{type};

    if ( $configMapId =~ /^component_(.+)/) {
        my $filebased_subflow = '';
        my $name_token = $1;
        
        ## here we need to get the information out of the file-based subflow
        #  each component commandSet will have one command to create the subflow
        #  and then a commandSet reference with a <fileName> that references
        #  the external file-based subflow.  Grab that.
        my $subcommandSet = $commandSet->first_child('commandSet') || 0;
        if ( $subcommandSet ) {
            my $fileName = $subcommandSet->first_child('fileName') || 0;
            if ($fileName) {
                $filebased_subflow = $fileName->text;
            } else {
                ## we expected a fileName here
                ##  TODO: handle error?
            }
        } else {
            ## we expected a commandSet here.  
            ##  TODO: handle error?
        }
        
        print <<ComponeNTBlock;
<ul class='component' id='$name_token'>
    <h1><span><b>component</b>: $name_token</span></h1>
    <li><div class="component_progress_image"></div></li>
    <li>state: wait for update</li>
    <li class="actions">
        [view] [<a>xml</a>] [<a>conf</a>] [<a>update</a>]
    </li>
</ul>
<script>sendComponentUpdateRequest('./component_summary.cgi?pipeline=$filebased_subflow&ul_id=$name_token', updateComponent, '$name_token', '$filebased_subflow');</script>
ComponeNTBlock

    ## configMapId is just numeric when we have a serial or parallel command set grouping
    } elsif ( $configMapId =~ /^\d+$/) {

        print "<ul class='$type'>\n";

        ## some special elements are needed for parallel sets
        if ($type eq 'parallel') {
            print "    <h1><span><b>parallel group</b></span></h1>\n";
        } else {
            print "    <h1><span><b>serial group</b></span></h1>\n";
        }

        ## look at each child.
        parseCommandSetChildren( $commandSet );
        print "</ul>\n";

    
    } elsif ($configMapId eq 'start') {
        print "<ul class='start'>\n";
        print "    <h1><span><b>start</b></span></h1>\n";
        print "</ul>\n";
        
        parseCommandSetChildren( $commandSet );
    }
}


sub parseCommandSetChildren {
    my $commandSet = shift;
    
    ## look at each child.
    for my $child ( $commandSet->children() ) {
        ## if it is a command set, parse through it. 
        if ($child->gi eq 'commandSet') {
            parseCommandSet($child);
        }
    }
}


sub print_header {
    print <<HeAdER;

<html>

<head>
    <meta http-equiv="Content-Language" content="en-us">
    <meta http-equiv="Content-Type" content="text/html; charset=windows-1252">
    <title>pre-pre-alpha workflow interface prototype</title>
    <style type="text/css">
        body {
            font-family: verdana, helvetica, arial, sans-serif;
            font-size: 10px;
            margin: 5px;
            padding: 0px;
        }

        a {
            text-decoration: none;
            color: rgb(0,100,0);
            cursor: pointer;
            cursor: hand;
        }

        li {
            list-style-type: none; 
            clear: left;
        }
        li.messages {
            margin-top: 5px;
            margin-bottom: 5px;
            color: rgb(75,75,75);
        }
        li.pass_values {
            display: none;
        }
        li.actions {
            margin-top: 5px;
        }
        
        ul {
            width: 525px;
            padding-left: 5px;
            padding-bottom: 5px;
            margin-left: 20px;
        }
        
        ul h1 {
            font-weight: normal; 
            font-size: 100%;
            margin-bottom: 0px;
        }
        
        ul.start, ul.end {
            border: 1px solid grey;
            width: 300px;
            background-color: rgb(220, 220, 220);
        }
        
        ul.parallel {
            border-left: 1px solid;
            border-color: rgb(0,100,0);
        }
        
        ul.component {
            border: 1px solid grey;
            margin-bottom: 5px;
        }
        
        #pipeline {
            font-weight: bold;
            margin-top: 5px;
            margin-left: 5px;
        }
        
        #pipelinesummary {
            border: 1px solid grey;
            width: 700px;
            padding-bottom: 5px;
        }
        #pipelinecommands {
            margin-left: 15px;
        }

        .pipelinestat {
            margin-left: 15px;
            display: inline;
            color: rgb(75,75,75);
        }
        
        div.component_label {
            float: left;
        }
        
        div.timer {
            float: right;
            color: rgb(150,150,150);
            margin-right: 5px;
        }
        div.component_progress_image {
            border: 1px solid black;
            padding: 0px;
            margin: 0px;
            height: 10px;
            width: 500px;
        }
        div.status_bar_portion {
            border: none;
            padding: 0px;
            margin: 0px;
            height: 10px;
            float: left;
        }

    </style>
    <script type="text/javascript">
        var timers = new Array();
        
        function requestComponentUpdate (subflow, ul_id) {
            // change border color to show we've started an update
            document.getElementById(ul_id).style.borderColor = 'black';
            
            // set the timer negative (to prevent conflicting updates)
            timers[ul_id] = -1;
            
            // change the countdown label to show we've started the update
            document.getElementById(ul_id + "_timer_label").innerHTML = "updating ...";

            sendComponentUpdateRequest('./component_summary.cgi?pipeline=' + subflow + '&ul_id=' + ul_id, updateComponent, ul_id, subflow);
        }
        
        function startAutoUpdate (subflow, ul_id, updateinterval) {
            // initialize this timer
            timers[ul_id] = updateinterval;
            componentCountdown(subflow, ul_id);
        }
        
        function stopAutoUpdate (ul_id) {
            timers[ul_id] = -1;
            
            // fix (clear out) the timer label
            document.getElementById(ul_id + '_timer_label').innerHTML = 'update stopped<span id="' + ul_id + '_counter"></span>';

            // mark that we're not updating this component
            document.getElementById(ul_id + '_continue_update').innerHTML = 0;            
        }
        
        function componentCountdown (subflow, ul_id) {
            // first check and see if the timer is negative, which would indicate a manual interruption
            if (timers[ul_id] < 0) {
                // quit the function
                return 1;
            }
        
            timers[ul_id]--;
            
            document.getElementById(ul_id + '_counter').innerHTML = timers[ul_id];
            
            if (timers[ul_id] > 0) {
                window.setTimeout( "componentCountdown('" + subflow + "', '" + ul_id + "')", 1000);
            } else {
                requestComponentUpdate( subflow, ul_id );
            }
        }
        

        
        // threadsafe asynchronous XMLHTTPRequest code
        function sendComponentUpdateRequest(url, callback, component, pipeline) {
            // inner functions below.  using these, reassigning the onreadystatechange
            // function won't stomp over earlier requests
            
            function ajaxBindCallback() {
                // progressive transitions are from 0 .. 4
                if (ajaxRequest.readyState == 4) {
                    // 200 is the successful response code
                    if (ajaxRequest.status == 200) {
                        ajaxCallback (ajaxRequest.responseText, component, pipeline, 41);
                    } else {
                        // error handling here
                        
                    }
                }
            }
            
            var ajaxRequest = null;
            var ajaxCallback = callback;
            
            // bind the call back, then do the request
            if (window.XMLHttpRequest) {
                // mozilla, firefox, etc will get here
                ajaxRequest = new XMLHttpRequest();
                ajaxRequest.onreadystatechange = ajaxBindCallback;
                ajaxRequest.open("GET", url, true);
                ajaxRequest.send(null);
            } else if (window.ActiveXObject) {
                // IE, of course, has its own way
                ajaxRequest = new ActiveXObject("Microsoft.XMLHTTP");
                
                if (ajaxRequest) {
                    ajaxRequest.onreadystatechange = ajaxBindCallback;
                    ajaxRequest.open("GET", url, true);
                    ajaxRequest.send();
                }
            }
            
        }
        
        function updateComponent (sometext, component, pipeline, updateinterval) {
            document.getElementById(component).innerHTML = '<li>' + sometext + '</li>';
            
            // change the countdown label back
            document.getElementById(component + "_timer_label").innerHTML = "update in <span id='" + component + "_counter'>10</span>s";
            
            // start the countdown for the next update of this component
            // if we are going to continue updating
            if ( document.getElementById(component + '_continue_update').innerHTML == 0 ) {
                // clear out the timer label since we're done updating
                document.getElementById(component + '_timer_label').innerHTML = '<span id="' + component + '_counter"></span>';

            } else {
                updateinterval = parseInt( document.getElementById(component + '_continue_update').innerHTML );
                startAutoUpdate(pipeline, component, parseInt(updateinterval));
            }
            
            // change border color back to show we've finished an update
            document.getElementById(component).style.borderColor = 'grey';
        }
        
        var pipeline_update_req;
        timers['pipeline'] = 21;
        
        function getPipelineUpdate(url) {
            // set the border and label to show update
            document.getElementById('pipelinesummary').style.borderColor = 'black';
        
            // Internet Explorer
            try { pipeline_update_req = new ActiveXObject("Msxml2.XMLHTTP"); }
            catch(e) {
                try { pipeline_update_req = new ActiveXObject("Microsoft.XMLHTTP"); }
                catch(oc) { pipeline_update_req = null; }
            }

            // Mozilla/Safari
            if (!pipeline_update_req && typeof XMLHttpRequest != "undefined") { 
                pipeline_update_req = new XMLHttpRequest(); 
            }

            // Call the processPipelineUpdate() function when the page has loaded
            if (pipeline_update_req != null) {
                pipeline_update_req.onreadystatechange = processPipelineUpdate;
                pipeline_update_req.open("GET", url, true);
                pipeline_update_req.send(null);
            }
        }
        
        function processPipelineUpdate() {
            // The page has loaded and the HTTP status code is 200 OK
            if (pipeline_update_req.readyState == 4 && pipeline_update_req.status == 200) {

                // write the contents of the div 
                document.getElementById('pipelinesummary').innerHTML = pipeline_update_req.responseText;
                
                // set the border back
                document.getElementById('pipelinesummary').style.borderColor = 'grey';
                
                // set the label back
                document.getElementById('pipeline_timer_label').innerHTML = "update in <span id='pipeline_counter'>20</span>s";
                
                // start the timer again
                timers['pipeline'] = 31;
                pipelineCountdown();
            }
        }
        
        function pipelineCountdown () {
            // first check and see if the timer is negative, which would indicate a manual interruption
            if (timers['pipeline'] < 0) {
                // quit the function
                return 1;
            }
        
            timers['pipeline']--;
            
            document.getElementById('pipeline_counter').innerHTML = timers['pipeline'];
            
            if (timers['pipeline'] > 0) {
                window.setTimeout( "pipelineCountdown()", 1000);
            } else {
                getPipelineUpdate( './pipeline_summary.cgi?pipeline=$xml_input' );
            }
        }
    </script>
</head>

<body>

<div id="debugbox"></div>

HeAdER
}

sub print_footer {
    print <<FooTER;
<ul class='end'>
    <h1><span><b>end</b></span></h1>
</ul>

</body>

</html>
FooTER
}
