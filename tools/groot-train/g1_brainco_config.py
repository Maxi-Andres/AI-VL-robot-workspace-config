"""GR00T modality config for the G1 with BrainCo hands (Unitree's G1_Brainco_* datasets):
one head camera, arms as deltas from the current joints, fingers as absolute targets."""
from gr00t.configs.data.embodiment_configs import register_modality_config
from gr00t.data.embodiment_tags import EmbodimentTag
from gr00t.data.types import ActionConfig, ActionFormat, ActionRepresentation, ActionType, ModalityConfig

PARTS = ["left_arm", "right_arm", "left_hand", "right_hand"]
ARM = ActionConfig(rep=ActionRepresentation.RELATIVE, type=ActionType.NON_EEF, format=ActionFormat.DEFAULT)
HAND = ActionConfig(rep=ActionRepresentation.ABSOLUTE, type=ActionType.NON_EEF, format=ActionFormat.DEFAULT)

g1_brainco_config = {
    "video": ModalityConfig(delta_indices=[0], modality_keys=["ego_view"]),
    "state": ModalityConfig(delta_indices=[0], modality_keys=PARTS),
    "action": ModalityConfig(delta_indices=list(range(16)), modality_keys=PARTS,
                             action_configs=[ARM, ARM, HAND, HAND]),
    "language": ModalityConfig(delta_indices=[0], modality_keys=["annotation.human.task_description"]),
}
register_modality_config(g1_brainco_config, embodiment_tag=EmbodimentTag.NEW_EMBODIMENT)
