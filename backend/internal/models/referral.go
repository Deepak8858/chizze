package models

import "time"

// Referral tracks a referral event
type Referral struct {
	ID             string    `json:"$id"`
	ReferrerUserID string    `json:"referrer_user_id"`
	ReferredUserID string    `json:"referred_user_id"`
	ReferralCode   string    `json:"referral_code"`
	Status         string    `json:"status"` // pending | completed | rewarded
	RewardAmount   float64   `json:"reward_amount"`
	CreatedAt      time.Time `json:"created_at"`
}

// ApplyReferralRequest is the body for POST /referrals/apply
type ApplyReferralRequest struct {
	ReferralCode string `json:"referral_code" binding:"required"`
}
