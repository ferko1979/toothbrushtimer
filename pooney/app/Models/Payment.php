<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Payment extends Model
{
    protected $fillable = ['order_id', 'gateway', 'gateway_reference', 'status', 'amount', 'currency', 'redirect_url', 'payload', 'last_checked_at'];
    protected $casts = ['payload' => 'array', 'amount' => 'decimal:2', 'last_checked_at' => 'datetime'];

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
