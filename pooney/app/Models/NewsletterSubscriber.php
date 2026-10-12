<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class NewsletterSubscriber extends Model
{
    protected $fillable = ['email', 'name', 'user_id', 'status', 'token', 'source', 'confirmed_at', 'unsubscribed_at', 'unsubscribe_reason'];
    protected $casts = ['confirmed_at' => 'datetime', 'unsubscribed_at' => 'datetime'];

    protected static function booted(): void
    {
        static::creating(fn (self $s) => $s->token ??= Str::random(48));
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'subscribed');
    }
}
