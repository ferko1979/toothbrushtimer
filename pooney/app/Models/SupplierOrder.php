<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupplierOrder extends Model
{
    protected $fillable = ['order_id', 'supplier', 'mode', 'status', 'supplier_order_id', 'cost', 'cost_currency', 'carrier', 'tracking_number', 'tracking_url', 'attempts', 'last_error', 'items', 'raw', 'placed_at', 'tracking_checked_at'];
    protected $casts = ['items' => 'array', 'raw' => 'array', 'cost' => 'decimal:2', 'placed_at' => 'datetime', 'tracking_checked_at' => 'datetime'];

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
