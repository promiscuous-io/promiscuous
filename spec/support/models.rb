module ModelsHelper
  def load_models
    load_models_mongoid if ORM.has(:mongoid)
    load_models_active_record if ORM.has(:active_record)
  end
end
