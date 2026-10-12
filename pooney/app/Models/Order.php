<?php

namespace App\Models;

use App\Enums\OrderStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Order extends Model
{
    protected $fillable = [
        'number', 'tracking_token', 'user_id', 'email', 'phone', 'customer_name', 'billing_address', 'shipping_address',
        'status', 'payment_status', 'payment_method', 'currency', 'subtotal_net', 'vat_total', 'shipping_gross',
        'discount_gross', 'total_gross', 'supplier_cost_total', 'customer_note', 'internal_note', 'locale', 'ip',
        'terms_accepted_at', 'newsletter_opt_in', 'invoice_number', 'invoice_token', 'invoice_path', 'invoice_provider',
        'placed_at', 'paid_at', 'shipped_at', 'delivered_at', 'cancelled_at', 'payment_reminder_sent_at',
        'review_request_sent_at', 'survey_sent_at',
    ];

    protected $casts = [
        'billing_address' => 'array', 'shipping_address' => 'array', 'status' => OrderStatus::class,
        'newsletter_opt_in' => 'boolean', 'terms_accepted_at' => 'datetime', 'placed_at' => 'datetime',
        'paid_at' => 'datetime', 'shipped_at' => 'datetime', 'delivered_at' => 'datetime', 'cancelled_at' => 'datetime',
        'payment_reminder_sent_at' => 'datetime', 'review_request_sent_at' => 'datetime', 'survey_sent_at' => 'datetime',
        'subtotal_net' => 'decimal:2', 'vat_total' => 'decimal:2', 'shipping_gross' => 'decimal:2',
        'discount_gross' => 'decimal:2', 'total_gross' => 'decimal:2', 'supplier_cost_total' => 'decimal:2',
    ];

    protected static function booted(): void
    {
        static::creating(function (self $order) {
            $order->tracking_token ??= Str::random(40);
            $order->number ??= static::generateNumber();
        });
    }

    /** Non-sequential, human readable order number, e.g. PN-26-4K7Q9M. */
    public static function generateNumber(): string
    {
        do {
            $number = 'PN-'.now()->format('y').'-'.strtoupper(Str::random(6));
            $number = strtr($number, ['0' => '7', 'O' => 'Q', 'I' => 'K', 'L' => 'M', '1' => '9']);
        } while (static::where('number', $number)->exists());

        return $number;
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class)->latest();
    }

    public function supplierOrders(): HasMany
    {
        return $this->hasMany(SupplierOrder::class);
    }

    public function shipmentEvents(): HasMany
    {
        return $this->hasMany(ShipmentEvent::class)->orderByDesc('occurred_at');
    }

    public function histories(): HasMany
    {
        return $this->hasMany(OrderStatusHistory::class)->latest();
    }

    public function complaints(): HasMany
    {
        return $this->hasMany(Complaint::class);
    }

    public function trackingUrl(): string
    {
        return route('orders.track', $this->tracking_token);
    }

    public function invoiceUrl(): ?string
    {
        return $this->invoice_token ? route('invoices.show', $this->invoice_token) : null;
    }

    public function isPaid(): bool
    {
        return $this->payment_status === 'paid';
    }
}
