<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ShipmentEvent extends Model
{
    protected $fillable = ['order_id', 'supplier_order_id', 'status', 'description', 'location', 'occurred_at', 'hash', 'customer_notified_at'];
    protected $casts = ['occurred_at' => 'datetime', 'customer_notified_at' => 'datetime'];
}
