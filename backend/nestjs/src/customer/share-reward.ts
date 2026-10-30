export type ShareRewardDecision = "disabled" | "already_claimed" | "granted";

/// Decides the outcome of a share-reward claim. Zero or negative points
/// disable the reward; an account that already claimed never gets it again.
export function decideShareReward(
  rewardPoints: bigint,
  alreadyClaimed: boolean,
): ShareRewardDecision {
  if (rewardPoints <= BigInt(0)) return "disabled";
  return alreadyClaimed ? "already_claimed" : "granted";
}
