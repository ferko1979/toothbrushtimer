<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ComplaintMessage extends Model
{
    protected $fillable = ['complaint_id', 'user_id', 'author', 'body'];
}
