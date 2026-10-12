<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Page extends Model
{
    protected $fillable = ['slug', 'title', 'body', 'is_published', 'show_in_footer', 'sort', 'version_published_at'];
    protected $casts = ['is_published' => 'boolean', 'show_in_footer' => 'boolean', 'version_published_at' => 'datetime'];
}
