#!/usr/bin/perl

# Copyright 2013 C & P Bibliography Services
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;
use CGI qw ( -utf8 );
use C4::Output;
use C4::Auth;
use C4::AuthoritiesMarc;
use Koha::MetadataRecord::Authority;
use C4::Koha;
use C4::Biblio;

my $input  = new CGI;
my @authid = $input->multi_param('authid');
my $merge  = $input->param('merge');

my @errors;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "authorities/merge.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { editauthorities => 1 },
    }
);

#------------------------
# Merging
#------------------------
if ($merge) {

    # Creating a new record from the html code
    my $record   = TransformHtmlToMarc($input, 0);
    my $recordid1   = $input->param('recordid1');
    my $recordid2   = $input->param('recordid2');
    my $typecode = $input->param('frameworkcode');

    # Rewriting the leader
    $record->leader( GetAuthority($recordid1)->leader() );

    # Modifying the reference record
    # This triggers a merge for the biblios attached to $recordid1
    ModAuthority( $recordid1, $record, $typecode );

    # Now merge for biblios attached to $recordid2
    # We ignore dontmerge now, since recordid2 is deleted
    my $MARCfrom = GetAuthority( $recordid2 );
    merge( $recordid2, $MARCfrom, $recordid1, $record );

    # Deleting the other record
    DelAuthority( $recordid2 );

    # Parameters
    $template->param(
        result  => 1,
        recordid1 => $recordid1
    );

    #-------------------------
    # Show records to merge
    #-------------------------
}
else {
    my $mergereference = $input->param('mergereference');
    $template->{'VARS'}->{'mergereference'} = $mergereference;

    if ( scalar(@authid) != 2 ) {
        push @errors, { code => "WRONG_COUNT", value => scalar(@authid) };
    }
    else {
        my $recordObj1 = Koha::MetadataRecord::Authority->get_from_authid($authid[0]) || Koha::MetadataRecord::Authority->new();
        my $recordObj2;

        if (defined $mergereference && $mergereference eq 'breeding') {
            $recordObj2 =  Koha::MetadataRecord::Authority->get_from_breeding($authid[1]) || Koha::MetadataRecord::Authority->new();
        } else {
            $recordObj2 =  Koha::MetadataRecord::Authority->get_from_authid($authid[1]) || Koha::MetadataRecord::Authority->new();
        }

        if ($mergereference) {

            my $framework;
            if ( $recordObj1->authtypecode ne $recordObj2->authtypecode && $mergereference ne 'breeding' ) {
                $framework = $input->param('frameworkcode')
                  or push @errors, { code => 'FRAMEWORK_NOT_SELECTED' };
            }
            else {
                $framework = $recordObj1->authtypecode;
            }
            if ($mergereference eq 'breeding') {
                $mergereference = $authid[0];
            }

            # Getting MARC Structure
            my $tagslib = GetTagsLabels( 1, $framework );
            foreach my $field ( keys %$tagslib ) {
                if ( defined $tagslib->{$field}->{'tab'} && $tagslib->{$field}->{'tab'} eq ' ' ) {
                    $tagslib->{$field}->{'tab'} = 0;
                }
            }

            #Setting $notreference
            my $notreference = $authid[1];
            if($mergereference == $notreference){
                $notreference = $authid[0];
                #Swap so $recordObj1 is always the correct merge reference
                ($recordObj1, $recordObj2) = ($recordObj2, $recordObj1);
            }

            # Creating a loop for display

            my @records = (
                {
                    recordid => $mergereference,
                    record => $recordObj1->record,
                    frameworkcode => $recordObj1->authtypecode,
                    display => $recordObj1->createMergeHash($tagslib),
                    reference => 1,
                },
                {
                    recordid => $notreference,
                    record => $recordObj2->record,
                    frameworkcode => $recordObj2->authtypecode,
                    display => $recordObj2->createMergeHash($tagslib),
                },
            );

            # Parameters
            $template->param(
                recordid1        => $mergereference,
                recordid2        => $notreference,
                records        => \@records,
                framework      => $framework,
            );
        }
        else {

            # Ask the user to choose which record will be the kept
            $template->param(
                choosereference => 1,
                recordid1         => $authid[0],
                recordid2         => $authid[1],
                title1          => $recordObj1->authorized_heading,
                title2          => $recordObj2->authorized_heading,
            );
            if ( $recordObj1->authtypecode ne $recordObj2->authtypecode ) {
                my $authority_types = Koha::Authority::Types->search( {}, { order_by => ['authtypecode'] } );
                my @frameworkselect;
                while ( my $authority_type = $authority_types->next ) {
                    my %row = (
                        value => $authority_type->authtypecode,
                        frameworktext => $authority_type->authtypetext,
                    );
                    push @frameworkselect, \%row;
                }
                $template->param(
                    frameworkselect => \@frameworkselect,
                    frameworkcode1  => $recordObj1->authtypecode,
                    frameworkcode2  => $recordObj2->authtypecode,
                );
            }
        }
    }
}

my $authority_types = Koha::Authority::Types->search({}, { order_by => ['authtypetext']});
$template->param( authority_types => $authority_types );

if (@errors) {

    # Errors
    $template->param( errors => \@errors );
}

output_html_with_http_headers $input, $cookie, $template->output;
exit;

=head1 FUNCTIONS

=cut

# ------------------------
# Functions
# ------------------------
