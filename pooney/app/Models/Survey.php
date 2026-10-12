<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Survey extends Model
{
    protected $fillable = ['slug', 'title', 'intro', 'questions', 'is_active'];
    protected $casts = ['questions' => 'array', 'is_active' => 'boolean'];

    public function responses(): HasMany
    {
        return $this->hasMany(SurveyResponse::class);
    }
}
