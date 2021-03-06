#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2016 ByWater Solutions
# Copyright (C) 2017 Koha Development Team
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Test::More tests => 17;
use Test::Warn;

use MARC::Record;

use t::lib::TestBuilder;

use C4::Letters;
use C4::Members;
use C4::Biblio;
use Koha::Database;
use Koha::DateUtils;
use Koha::ArticleRequests;
use Koha::Biblio;
use Koha::Biblioitem;
use Koha::Item;
use Koha::Hold;
use Koha::NewsItem;
use Koha::Serial;
use Koha::Subscription;
use Koha::Suggestion;
use Koha::Checkout;
use Koha::Notice::Messages;
use Koha::Notice::Templates;
use Koha::Patron::Modification;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin();

my $builder = t::lib::TestBuilder->new();

my $dbh = C4::Context->dbh;
$dbh->{RaiseError} = 1;

$dbh->do(q|DELETE FROM letter|);

my $date = dt_from_string;

my $library = $builder->build( { source => 'Branch' } );
my $patron  = $builder->build( { source => 'Borrower' } );
my $patron2 = $builder->build( { source => 'Borrower' } );

my $biblio = Koha::Biblio->new(
    {
        title => 'Test Biblio'
    }
)->store();

my $biblioitem = Koha::Biblioitem->new(
    {
        biblionumber => $biblio->id()
    }
)->store();

my $item = Koha::Item->new(
    {
        biblionumber     => $biblio->id(),
        biblioitemnumber => $biblioitem->id()
    }
)->store();

my $hold = Koha::Hold->new(
    {
        borrowernumber => $patron->{borrowernumber},
        biblionumber   => $biblio->id()
    }
)->store();

my $news         = Koha::NewsItem->new()->store();
my $serial       = Koha::Serial->new()->store();
my $subscription = Koha::Subscription->new()->store();
my $suggestion   = Koha::Suggestion->new()->store();
my $checkout     = Koha::Checkout->new( { itemnumber => $item->id() } )->store();
my $modification = Koha::Patron::Modification->new( { verification_token => "TEST" } )->store();

my $prepared_letter;

my $sth =
  $dbh->prepare(q{INSERT INTO letter (module, code, name, title, content) VALUES ('test',?,'Test','Test',?)});

$sth->execute( "TEST_PATRON", "[% borrower.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_PATRON',
        tables      => {
            borrowers => $patron->{borrowernumber},
        },
    )
);
is( $prepared_letter->{content}, $patron->{borrowernumber}, 'Patron object used correctly with scalar' );

$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_PATRON',
        tables      => {
            borrowers => $patron,
        },
    )
);
is( $prepared_letter->{content}, $patron->{borrowernumber}, 'Patron object used correctly with hashref' );

$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_PATRON',
        tables      => {
            borrowers => [ $patron->{borrowernumber} ],
        },
    )
);
is( $prepared_letter->{content}, $patron->{borrowernumber}, 'Patron object used correctly with arrayref' );

$sth->execute( "TEST_BIBLIO", "[% biblio.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_BIBLIO',
        tables      => {
            biblio => $biblio->id(),
        },
    )
);
is( $prepared_letter->{content}, $biblio->id, 'Biblio object used correctly' );

$sth->execute( "TEST_LIBRARY", "[% branch.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_LIBRARY',
        tables      => {
            branches => $library->{branchcode}
        },
    )
);
is( $prepared_letter->{content}, $library->{branchcode}, 'Library object used correctly' );

$sth->execute( "TEST_ITEM", "[% item.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_ITEM',
        tables      => {
            items => $item->id()
        },
    )
);
is( $prepared_letter->{content}, $item->id(), 'Item object used correctly' );

$sth->execute( "TEST_NEWS", "[% news.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_NEWS',
        tables      => {
            opac_news => $news->id()
        },
    )
);
is( $prepared_letter->{content}, $news->id(), 'News object used correctly' );

$sth->execute( "TEST_HOLD", "[% hold.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_HOLD',
        tables      => {
            reserves => { borrowernumber => $patron->{borrowernumber}, biblionumber => $biblio->id() },
        },
    )
);
is( $prepared_letter->{content}, $hold->id(), 'Hold object used correctly' );

eval {
    $prepared_letter = GetPreparedLetter(
        (
            module      => 'test',
            letter_code => 'TEST_HOLD',
            tables      => {
                reserves => [ $patron->{borrowernumber}, $biblio->id() ],
            },
        )
    )
};
my $croak = $@;
like( $croak, qr{^Multiple foreign keys \(table reserves\) should be passed using an hashref.*}, "GetPreparedLetter should not be called with arrayref for multiple FK" );

# Bug 16942
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_HOLD',
        tables      => {
            'branches'    => $library,
            'borrowers'   => $patron,
            'biblio'      => $biblio->id,
            'biblioitems' => $biblioitem->id,
            'reserves'    => $hold->unblessed,
            'items'       => $hold->itemnumber,
        }
    )
);
is( $prepared_letter->{content}, $hold->id(), 'Hold object used correctly' );

$sth->execute( "TEST_SERIAL", "[% serial.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_SERIAL',
        tables      => {
            serial => $serial->id()
        },
    )
);
is( $prepared_letter->{content}, $serial->id(), 'Serial object used correctly' );

$sth->execute( "TEST_SUBSCRIPTION", "[% subscription.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_SUBSCRIPTION',
        tables      => {
            subscription => $subscription->id()
        },
    )
);
is( $prepared_letter->{content}, $subscription->id(), 'Subscription object used correctly' );

$sth->execute( "TEST_SUGGESTION", "[% suggestion.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_SUGGESTION',
        tables      => {
            suggestions => $suggestion->id()
        },
    )
);
is( $prepared_letter->{content}, $suggestion->id(), 'Suggestion object used correctly' );

$sth->execute( "TEST_ISSUE", "[% checkout.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_ISSUE',
        tables      => {
            issues => $item->id()
        },
    )
);
is( $prepared_letter->{content}, $checkout->id(), 'Checkout object used correctly' );

$sth->execute( "TEST_MODIFICATION", "[% patron_modification.id %]" );
$prepared_letter = GetPreparedLetter(
    (
        module      => 'test',
        letter_code => 'TEST_MODIFICATION',
        tables      => {
            borrower_modifications => $modification->verification_token,
        },
    )
);
is( $prepared_letter->{content}, $modification->id(), 'Patron modification object used correctly' );

subtest 'regression tests' => sub {
    plan tests => 2;

    my $library = $builder->build( { source => 'Branch' } );
    my $patron  = $builder->build( { source => 'Borrower' } );
    my $biblio = Koha::Biblio->new({title => 'Test Biblio'})->store->unblessed;
    my $biblioitem = Koha::Biblioitem->new({biblionumber => $biblio->{biblionumber}})->store()->unblessed;
    my $item1 = Koha::Item->new(
        {
            biblionumber     => $biblio->{biblionumber},
            biblioitemnumber => $biblioitem->{biblioitemnumber},
        }
    )->store->unblessed;
    my $item2 = Koha::Item->new(
        {
            biblionumber     => $biblio->{biblionumber},
            biblioitemnumber => $biblioitem->{biblioitemnumber},
        }
    )->store->unblessed;

    subtest 'ACQ_NOTIF_ON_RECEIV ' => sub {
        plan tests => 1;
        my $code = 'ACQ_NOTIF_ON_RECEIV';
        my $branchcode = $library->{branchcode};
        my $order = $builder->build({ source => 'Aqorder' });

        my $template = q|
            Dear <<borrowers.firstname>> <<borrowers.surname>>,
            The order <<aqorders.ordernumber>> (<<biblio.title>>) has been received.
            Your library.
        |;
        my $params = { code => $code, branchcode => $branchcode, tables => { branches => $library, borrowers => $patron, biblio => $biblio, aqorders => $order } };
        my $letter = process_letter( { template => $template, %$params });
        my $tt_template = q|
            Dear [% borrower.firstname %] [% borrower.surname %],
            The order [% order.ordernumber %] ([% biblio.title %]) has been received.
            Your library.
        |;
        my $tt_letter = process_letter( { template => $tt_template, %$params });

        is( $tt_letter->{content}, $letter->{content}, );
    };

    subtest 'AR_*' => sub {
        plan tests => 2;
        my $code = 'AR_CANCELED';
        my $branchcode = $library->{branchcode};

        my $template = q|
            <<borrowers.firstname>> <<borrowers.surname>> (<<borrowers.cardnumber>>)

            Your request for an article from <<biblio.title>> (<<items.barcode>>) has been canceled for the following reason:

            <<article_requests.notes>>

            Article requested:
            Title: <<article_requests.title>>
            Author: <<article_requests.author>>
            Volume: <<article_requests.volume>>
            Issue: <<article_requests.issue>>
            Date: <<article_requests.date>>
            Pages: <<article_requests.pages>>
            Chapters: <<article_requests.chapters>>
            Notes: <<article_requests.patron_notes>>
        |;
        reset_template( { template => $template, code => $code, module => 'circulation' } );
        my $article_request = $builder->build({ source => 'ArticleRequest' });
        Koha::ArticleRequests->find( $article_request->{id} )->cancel;
        my $letter = Koha::Notice::Messages->search( {}, { order_by => { -desc => 'message_id' } } )->next;

        my $tt_template = q|
            [% borrower.firstname %] [% borrower.surname %] ([% borrower.cardnumber %])

            Your request for an article from [% biblio.title %] ([% item.barcode %]) has been canceled for the following reason:

            [% article_request.notes %]

            Article requested:
            Title: [% article_request.title %]
            Author: [% article_request.author %]
            Volume: [% article_request.volume %]
            Issue: [% article_request.issue %]
            Date: [% article_request.date %]
            Pages: [% article_request.pages %]
            Chapters: [% article_request.chapters %]
            Notes: [% article_request.patron_notes %]
        |;
        reset_template( { template => $tt_template, code => $code, module => 'circulation' } );
        Koha::ArticleRequests->find( $article_request->{id} )->cancel;
        my $tt_letter = Koha::Notice::Messages->search( {}, { order_by => { -desc => 'message_id' } } )->next;
        is( $tt_letter->content, $letter->content, 'Compare AR_* notices' );
        isnt( $tt_letter->message_id, $letter->message_id, 'Comparing AR_* notices should compare 2 different messages' );
    };
};

subtest 'loops' => sub {
    plan tests => 2;
    my $code = "TEST";
    my $module = "TEST";

    subtest 'primary key is AI' => sub {
        plan tests => 1;
        my $patron_1 = $builder->build({ source => 'Borrower' });
        my $patron_2 = $builder->build({ source => 'Borrower' });

        my $template = q|[% FOREACH patron IN borrowers %][% patron.surname %][% END %]|;
        reset_template( { template => $template, code => $code, module => $module } );
        my $letter = GetPreparedLetter( module => $module, letter_code => $code, loops => { borrowers => [ $patron_1->{borrowernumber}, $patron_2->{borrowernumber} ] } );
        my $expected_letter = join '', ( $patron_1->{surname}, $patron_2->{surname} );
        is( $letter->{content}, $expected_letter, );
    };

    subtest 'foreign key is used' => sub {
        plan tests => 1;
        my $patron_1 = $builder->build({ source => 'Borrower' });
        my $patron_2 = $builder->build({ source => 'Borrower' });
        my $checkout_1 = $builder->build({ source => 'Issue', value => { borrowernumber => $patron_1->{borrowernumber} } } );
        my $checkout_2 = $builder->build({ source => 'Issue', value => { borrowernumber => $patron_1->{borrowernumber} } } );

        my $template = q|[% FOREACH checkout IN checkouts %][% checkout.issue_id %][% END %]|;
        reset_template( { template => $template, code => $code, module => $module } );
        my $letter = GetPreparedLetter( module => $module, letter_code => $code, loops => { issues => [ $checkout_1->{itemnumber}, $checkout_2->{itemnumber} ] } );
        my $expected_letter = join '', ( $checkout_1->{issue_id}, $checkout_2->{issue_id} );
        is( $letter->{content}, $expected_letter, );
    };
};

sub reset_template {
    my ( $params ) = @_;
    my $template   = $params->{template};
    my $code       = $params->{code};
    my $module     = $params->{module} || 'test_module';

    Koha::Notice::Templates->search( { code => $code } )->delete;
    Koha::Notice::Template->new(
        {
            module                 => $module,
            code                   => $code,
            branchcode             => '',
            name                   => $code,
            title                  => $code,
            message_transport_type => 'email',
            content                => $template
        }
    )->store;
}

sub process_letter {
    my ($params)   = @_;
    my $template   = $params->{template};
    my $tables     = $params->{tables};
    my $substitute = $params->{substitute};
    my $code       = $params->{code};
    my $module     = $params->{module} || 'test_module';
    my $branchcode = $params->{branchcode};

    reset_template( $params );

    my $letter = C4::Letters::GetPreparedLetter(
        module      => $module,
        letter_code => $code,
        branchcode  => '',
        tables      => $tables,
        substitute  => $substitute,
    );
    return $letter;
}
