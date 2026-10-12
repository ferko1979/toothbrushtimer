<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class EmailLog extends Model
{
    protected $fillable = ['to', 'template_key', 'subject', 'driver', 'status', 'error', 'related_type', 'related_id', 'sent_at'];
    protected $casts = ['sent_at' => 'datetime'];
}
