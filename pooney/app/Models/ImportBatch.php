<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ImportBatch extends Model
{
    protected $fillable = ['source', 'status', 'total', 'created_count', 'updated_count', 'failed_count', 'log', 'user_id'];
    protected $casts = ['log' => 'array'];
}
