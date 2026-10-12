<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

class ProductImage extends Model
{
    protected $fillable = ['product_id', 'path', 'source_url', 'alt', 'sort'];
    protected $hidden = ['source_url'];

    public function url(): string
    {
        return Storage::disk('public')->url($this->path);
    }
}
