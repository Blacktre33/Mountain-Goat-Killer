"""Regenerate tools/audio/voice_manifest.json from the recorded Higgsfield jobs.

Voices (Higgsfield seed_audio presets): the Herdkeeper's inner narration is
"Brooks" (dark, warm, low), Varkas is "Vlad" (very low, gravelly; speech slowed
and pitched down 3 units), the pack barks are "Landon" and "Gideon".
Only text that already exists in scripts/story.gd, plus short in-world barks
and Varkas taunts, is spoken.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CDN = "https://d8j0ntlcm91z4.cloudfront.net/user_2zOO5xDxXFn8mw3MAKxGoRsvsu6/"

VOICES = {
	"keeper": {"name": "Brooks", "voice_id": "c2acff45-84b2-4974-892d-89fa2d4e5598", "speech_rate": -12},
	"varkas": {"name": "Vlad", "voice_id": "e5666b9c-99a2-4fac-8b4e-abee078b186d", "speech_rate": -18, "pitch_rate": -3},
	"pack_a": {"name": "Landon", "voice_id": "dc1c0a41-53cd-53af-aec5-ab637840505f", "speech_rate": 10},
	"pack_b": {"name": "Gideon", "voice_id": "1ad38ba4-9cc4-4f2f-9fde-b0fefdf67ae5", "speech_rate": 10},
}

# id, speaker, job id, cdn file stem, text
LINES = [
	("intro_0", "keeper", "a9ba4ffc-5b13-44eb-8382-d35775a701a7", "hf_20260929_043050", "Nine neck-bells. Nine names. One great bell to call the herd home."),
	("intro_1", "keeper", "723e2cfa-5be5-416a-b317-1bb89796d373", "hf_20260929_043050", "Varkas came in the blue hour. By dawn the birthing pen was black-red, and our bells hung from his killers."),
	("intro_2", "keeper", "5b430707-e90d-4e26-baf4-26c2f523d41c", "hf_20260929_043050", "Maren pushed me beneath the ice trough before his knife found her. Ten winters later, I have come back with her carbine."),
	("intro_3", "keeper", "8eac03ae-2113-4f35-b277-649fb1543ae0", "hf_20260929_043050", "Cross three scars of this mountain. Take every name. Ring the mother bell. Put Varkas in the ground."),
	("memory_0", "keeper", "1870eca9-f535-4dbc-88a3-586facd1b4e9", "hf_20260929_043050", "Asha taught me to step where the needles were thick. Her killer wore her bell to warn the others when he fed."),
	("memory_1", "keeper", "67770ccc-9a05-4ad0-9bb7-eb4b85f8e1d8", "hf_20260929_043050", "Rowan mended every broken strap in the fold. I have to cut his bell free. The leather has grown into the rust."),
	("memory_2", "keeper", "6892578c-dae5-4548-a44d-eb770f61c1ba", "hf_20260929_043050", "Tember built the ice trough. He made it deep enough for a winter's water. Deep enough to hide one child."),
	("memory_3", "keeper", "b016abae-3a2c-4845-8417-8315891ec2b5", "hf_20260929_043134", "Lissa could name a missing goat by the silence in the herd. Four bells answer now. The mother bell will hear us."),
	("memory_4", "keeper", "8f055c92-1b4e-4c50-b10d-7c0eb8aaf6bb", "hf_20260929_043051", "Hollin hauled the abbey's first stones. His bell is dented flat on one side. I turn that side into my palm."),
	("memory_5", "keeper", "0ead9966-3830-4244-8a09-1bca561eef34", "hf_20260929_043050", "Brae stitched Maren's wounds after the rockfall. There was nobody left to stitch hers. I wipe the bell on my coat."),
	("memory_6", "keeper", "ccf18a15-4b28-4db4-bf72-c0b041031db5", "hf_20260929_043050", "Sorrel kept seed beneath the hearth through every lean winter. The hearth is cold. I keep the bell warm in my hand."),
	("memory_7", "keeper", "5912060d-8f83-41f9-bff6-5d1efca11f8e", "hf_20260929_043050", "Maren put her hand over my mouth beneath the trough. Stay quiet, she said. I carried her carbine here. I carry her name out."),
	("memory_8", "keeper", "d1acb63d-28e6-4bef-9f71-44a3037cf0cd", "hf_20260929_043134", "Orin was small enough to sleep against my ribs. Varkas wore his bell through ten winters. He will not wear it through another dawn."),
	("chapter_trailhead", "keeper", "73f4587b-d09e-41df-b78c-26b46846e2bf", "hf_20260929_043135", "The pines kept the smell for ten winters: sap, cold iron, and the blood they could not bury."),
	("chapter_homestead", "keeper", "8bbb2463-4d3c-4bd3-a268-bb4db9f3ec3b", "hf_20260929_043134", "They sleep inside our fence. Four of our bells knock against their armour when they breathe."),
	("chapter_shrine", "keeper", "6f4c3c49-c6c5-4b71-bd5f-504a7fdb30f7", "hf_20260929_043216", "The snow thins here. Bone shows through the old red earth. Four names will wake the mother bell."),
	("chapter_ascent", "keeper", "67d78c9e-0a4b-41f0-84df-52a9b4d55789", "hf_20260929_043217", "The bell has given the dead a voice. I carry it uphill, one shot at a time."),
	("chapter_gate", "keeper", "a473d9c1-81fd-41c4-b053-caaf42cf7dc6", "hf_20260929_043216", "Eight names open the abbey our herd built. The ninth still knocks against Varkas' throat. Orin. My little brother."),
	("bell_rung", "keeper", "c2c41d04-313b-4933-a7a5-a07919b5b480", "hf_20260929_043217", "The mother bell tears the silence open. Every wolverine looks uphill. Every stolen bell answers."),
	("boss_phase_1", "keeper", "bebae27c-b2aa-4205-963e-9513386cc6b4", "hf_20260929_043216", "Varkas lowers his plated head. Orin's bell knocks once against his throat."),
	("boss_phase_2", "keeper", "dd9c1975-80d2-4ce3-9d75-69065e8e6396", "hf_20260929_043216", "His hide splits under the iron. Four memorial lamps spit red; he howls, and the last of the pack comes running."),
	("boss_phase_3", "keeper", "9462fbd7-e03b-42f7-a202-b4b0d7c56299", "hf_20260929_043253", "The plates tear free. Eight names burn around him. He lowers the red horn; I remember Maren's hand. Be still. Let him commit. Then move."),
	("victory_0", "keeper", "615523b8-ac56-4105-995e-71256c3e0061", "hf_20260929_043253", "Varkas dies beneath the bell he stole from Orin. I leave his iron in the mud."),
	("victory_1", "keeper", "2b145351-9b3c-4abb-8e19-b695c082cf10", "hf_20260929_043253", "I do not wear the nine bells as trophies. I carry them down through ash, bone, and snow."),
	("victory_2", "keeper", "1edbe0ec-1c7d-4a78-89f5-9316213a7c25", "hf_20260929_043253", "At dawn the mother bell calls them home: Asha. Rowan. Tember. Lissa. Hollin. Brae. Sorrel. Maren. Orin."),
	("victory_3", "keeper", "16c2d300-6d45-452e-a267-ebf150df99cf", "hf_20260929_043253", "The mountain remembers. This time, it speaks our names instead of his."),
	("varkas_alert_0", "varkas", "49c6bb93-8c3f-4453-9032-51e7e377ad01", "hf_20260929_043338", "Another goat, climbing my mountain."),
	("varkas_alert_1", "varkas", "88c83106-1958-4d53-8627-82de1be1fd9f", "hf_20260929_043337", "The bells told me you were coming."),
	("varkas_phase_1", "varkas", "e9e28171-a03c-418c-84f9-205a925c1589", "hf_20260929_043338", "I wear their names. Take one, if you can."),
	("varkas_phase_2", "varkas", "4014f7cd-7eba-4a9c-84ce-0e11720507a0", "hf_20260929_043337", "Pack! Tear it down!"),
	("varkas_phase_3", "varkas", "0ae312c9-2f1f-411c-9bb0-d9e875edecc3", "hf_20260929_043337", "Come, then. Meet the horn."),
	("varkas_hurt", "varkas", "c7401795-ba2f-44f0-a781-e7ed63364397", "hf_20260929_043337", "Is that all the herd left?"),
	("varkas_kill_1", "varkas", "278cd8b4-d08c-44f1-8f5a-47e477637a3d", "hf_20260929_043413", "Down you go, with the rest."),
	("varkas_final", "varkas", "78c7f965-5812-42f1-a366-d48dad3dac4f", "hf_20260929_043413", "Ring it, then. I hear them anyway."),
	("bark_contact_a", "pack_a", "e91a6b4b-bfce-4f8e-9e8e-fdc0c8a94cad", "hf_20260929_043414", "Contact! Contact!"),
	("bark_lost_a", "pack_a", "4cdd92f3-914a-4461-baca-3287a0bad054", "hf_20260929_043413", "Lost him."),
	("varkas_kill_0", "varkas", "20b5bfd7-611a-447f-b52f-253bd349a1c6", "hf_20260929_044007", "The mountain keeps the goat."),
	("bark_contact_b", "pack_b", "fcbab017-07ce-45ab-9e88-119d5e1cd20f", "hf_20260929_044007", "There he is!"),
	("bark_lost_b", "pack_b", "b00b08c6-16b9-41d5-bd42-0866ffc06314", "hf_20260929_044007", "Where did he go?"),
	("bark_flank_a", "pack_a", "83f268ea-f353-4e11-9c57-f122e940cd8a", "hf_20260929_044007", "Flank him!"),
	("bark_flank_b", "pack_b", "d857ec7b-02ab-4e47-ac07-fccc447ba44b", "hf_20260929_044007", "Go around!"),
	("bark_body_a", "pack_a", "98506bd4-1354-4331-b130-7386e17c32d0", "hf_20260929_044053", "Body! Someone's here!"),
	("bark_body_b", "pack_b", "4531eb03-02a9-4c2d-9d75-218f9df074be", "hf_20260929_044053", "Someone killed him. Find them."),
]

def main():
	lines = []
	for lid, speaker, job, stamp, text in LINES:
		lines.append({"id": lid, "speaker": speaker, "job_id": job, "text": text, "url": "%s%s_%s.wav" % (CDN, stamp, job)})
	with open(os.path.join(HERE, "voice_manifest.json"), "w") as fh:
		json.dump({"voices": VOICES, "lines": lines}, fh, indent=1)
	print(len(lines), "lines")


if __name__ == "__main__":
	main()
