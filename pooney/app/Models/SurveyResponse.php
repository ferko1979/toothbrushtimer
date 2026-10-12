<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SurveyResponse extends Model
{
    protected $fillable = ['survey_id', 'user_id', 'order_id', 'email', 'answers'];
    protected $casts = ['answers' => 'array'];
}
