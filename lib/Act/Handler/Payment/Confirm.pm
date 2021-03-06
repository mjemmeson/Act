package Act::Handler::Payment::Confirm;
use strict;

use Act::Config;
use Act::Email;
use Act::I18N;
use Act::Order;
use Act::Payment;
use Act::Template;
use Act::User;

sub handler
{
    # we aren't dispatched by Act::Dispatcher
    $Request{args} = { map { my $v = $Request{r}->param($_);
                             $_ => defined($v) ? $v : ''
                           } $Request{r}->param
                     };

    # load appropriate plugin, hardwired to the url in httpd.conf
    my $type = $Request{r}->dir_config('ActPaymentType');
    my $plugin = Act::Payment::load_plugin($type);

    # verify payment
    my ($verified, $paid, $order_id) = $plugin->verify($Request{args});
    my $order;
    if ($verified && $paid && $order_id) {
        $order = Act::Order->new(order_id => $order_id);
        if ($order && $order->status eq 'init') {
            # update order
            $order->update(status => 'paid');
            # send email notification
            _notify($order, $plugin);
        }
    }
    $plugin->create_response($verified, $order);
}

sub _notify
{
    my ($order, $plugin) = @_;

    # remember, we aren't dispatched by Act::Dispatcher,
    # so load appropriate conference configuration
    # and set up some context
    $Config = Act::Config::get_config($Request{conference} = $order->conf_id);
    $Request{user} = Act::User->new(user_id => $order->user_id);
    $Request{language} = $Request{user}->language || $Config->general_default_language;
    $Request{loc} = Act::I18N->get_handle($Request{language});
    my $template = Act::Template->new; # context-dependent, can't be global

    # generate subject and body from templates
    my %output;
    for my $slot (qw(subject body)) {
        $template->variables(order => $order);
        $template->process("payment/notify_$slot", \$output{$slot});
    }
    # send the notification email
    my %args = (
        from    => $Config->email_sender_address,
        to      => $Request{user}->email,
        bcc     => [ split /\s*,\s*/, $plugin->_type_config('notify_bcc') ],
        xheaders => {
            'X-Act' => join(
                ' ', 'payment confirmation:',
                user  => $order->user_id,
                conf  => $Request{conference},
                order => $order->order_id,
            ),
            },
        %output,
    );
    push @{$args{bcc}}, $Config->payment_notify_address
        if $Config->payment_notify_address;
    Act::Email::send(%args);
}

1;
__END__

=head1 NAME

Act::Handler::Payment::Confirm - confirm a payment.

=head1 DESCRIPTION

This handler is called by the bank with the status
of a payment.

See F<DEVDOC> for a complete discussion on handlers.

=cut
