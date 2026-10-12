<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Complaint extends Model
{
    public const TYPES = [
        'damaged' => 'Sérült termék',
        'missing' => 'Hiányzó tétel',
        'wrong_item' => 'Nem a rendelt termék',
        'not_arrived' => 'Nem érkezett meg',
        'withdrawal' => 'Elállás (14 nap)',
        'other' => 'Egyéb',
    ];

    public const STATUSES = [
        'open' => 'Nyitott',
        'in_progress' => 'Folyamatban',
        'waiting_customer' => 'Válaszra vár',
        'resolved' => 'Megoldva',
        'rejected' => 'Elutasítva',
    ];

    protected $fillable = ['number', 'order_id', 'order_item_id', 'user_id', 'email', 'type', 'description', 'attachments', 'status', 'resolution', 'refund_amount', 'resolved_at'];
    protected $casts = ['attachments' => 'array', 'resolved_at' => 'datetime', 'refund_amount' => 'decimal:2'];

    protected static function booted(): void
    {
        static::creating(fn (self $c) => $c->number ??= 'RK-'.now()->format('y').'-'.strtoupper(Str::random(5)));
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(OrderItem::class, 'order_item_id');
    }

    public function messages(): HasMany
    {
        return $this->hasMany(ComplaintMessage::class)->oldest();
    }
}
