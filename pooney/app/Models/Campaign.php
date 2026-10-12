<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Campaign extends Model
{
    protected $fillable = ['name', 'subject', 'body', 'audience', 'status', 'scheduled_at', 'sent_at', 'recipients_count'];
    protected $casts = ['scheduled_at' => 'datetime', 'sent_at' => 'datetime'];
}
